# Chapter 5 - WebSockets, Ajax & CORS

When thinking about realtime frameworks on the web, you usually don't give Sinatra (or Rails) much thought due to the general lack of options and support. That's understandable, but the Ruby WebSockets ecosystem has improved significantly and I can tell you from experience that you can definitely build production-ready real-time applications with Sinatra.

In this chapter I'll walk you through building a realtime chat application, setting up proper CORS handling for cross-origin requests, creating embeddable JavaScript widgets and building a live exception tracking system. There's quite a bit of ground to cover, so let's get into it.

## Understanding WebSockets

WebSockets provide full-duplex communication over a single TCP connection. Unlike traditional HTTP request-response cycles, WebSockets allow both client and server to send data at any time. This makes them perfect for real-time applications.

WebSockets provide the lower level technology making it possible for a persistent interactive session between a user's browser and your application server. Your application can listen for event-based messages and do something with those messages in realtime.

A good example would be a basic chat application: you don't want to have to refresh your browser each time to see new messages, you'd expect the new messages to appear in your chat window at the exact moment they get sent by the sender. Your browser is listening for a "new messages received" notification from the server and it will act accordingly when received.

Note: Browser support for WebSockets has come a long way and it's supported in almost all modern web browsers. The only exceptions are very old Android browsers and Opera Mini.

WebSockets has changed the way we build modern web applications much in the same way AJAX did a few years ago.

## Basic WebSocket Setup with Sinatra

We'll use the `faye-websocket` gem, which works with any Rack-compatible server including Puma:

```ruby
# Gemfile
gem 'sinatra'
gem 'faye-websocket'
gem 'puma'

# app.rb
require 'sinatra'
require 'faye/websocket'

get '/' do
  if Faye::WebSocket.websocket?(env)
    ws = Faye::WebSocket.new(env)

    ws.on :open do |event|
      puts "WebSocket connection opened"
      ws.send("Welcome to the chat!")
    end

    ws.on :message do |event|
      puts "Received: #{event.data}"
      ws.send("Echo: #{event.data}")
    end

    ws.on :close do |event|
      puts "WebSocket connection closed"
      ws = nil
    end

    ws.rack_response
  else
    erb :index
  end
end
```

## Realtime Chat Application

Let's build a production-ready chat system:

```ruby
# lib/chat_server.rb
class ChatServer
  def initialize
    @clients = {}
    @rooms = {}
  end
  
  def add_client(client_id, websocket, user_id, room_id)
    @clients[client_id] = {
      websocket: websocket,
      user_id: user_id,
      room_id: room_id,
      joined_at: Time.now
    }
    
    @rooms[room_id] ||= Set.new
    @rooms[room_id] << client_id
    
    broadcast_to_room(room_id, {
      type: 'user_joined',
      user_id: user_id,
      timestamp: Time.now.to_i
    }, exclude: client_id)
  end
  
  def remove_client(client_id)
    return unless client = @clients[client_id]
    
    room_id = client[:room_id]
    user_id = client[:user_id]
    
    @clients.delete(client_id)
    @rooms[room_id]&.delete(client_id)
    
    broadcast_to_room(room_id, {
      type: 'user_left',
      user_id: user_id,
      timestamp: Time.now.to_i
    })
  end
  
  def handle_message(client_id, message)
    return unless client = @clients[client_id]
    
    case message['type']
    when 'chat_message'
      handle_chat_message(client_id, message)
    when 'typing_start'
      handle_typing_indicator(client_id, true)
    when 'typing_stop'
      handle_typing_indicator(client_id, false)
    end
  end
  
  private
  
  def handle_chat_message(client_id, message)
    client = @clients[client_id]
    room_id = client[:room_id]
    user_id = client[:user_id]
    
    # Save message to database
    chat_message = ChatMessage.create!(
      user_id: user_id,
      room_id: room_id,
      content: message['content'],
      message_type: message['message_type'] || 'text'
    )
    
    # Broadcast to all clients in room
    broadcast_to_room(room_id, {
      type: 'new_message',
      message_id: chat_message.id,
      user_id: user_id,
      content: chat_message.content,
      timestamp: chat_message.created_at.to_i,
      user_name: User.find(user_id).name
    })
  end
  
  def handle_typing_indicator(client_id, is_typing)
    client = @clients[client_id]
    room_id = client[:room_id]
    user_id = client[:user_id]
    
    broadcast_to_room(room_id, {
      type: 'typing_indicator',
      user_id: user_id,
      is_typing: is_typing
    }, exclude: client_id)
  end
  
  def broadcast_to_room(room_id, message, exclude: nil)
    return unless room_clients = @rooms[room_id]
    
    room_clients.each do |client_id|
      next if client_id == exclude
      next unless client = @clients[client_id]
      
      begin
        client[:websocket].send(message.to_json)
      rescue => e
        puts "Error sending message to client #{client_id}: #{e.message}"
        remove_client(client_id)
      end
    end
  end
end

# app.rb
class App < Sinatra::Base
  configure do
    set :chat_server, ChatServer.new
  end
  
  get '/chat/:room_id' do
    @room_id = params[:room_id]
    @room = ChatRoom.find(@room_id)
    
    if Faye::WebSocket.websocket?(env)
      client_id = SecureRandom.uuid
      user_id = session[:user_id]
      ws = Faye::WebSocket.new(env)

      ws.on :open do |event|
        settings.chat_server.add_client(client_id, ws, user_id, @room_id)
      end

      ws.on :message do |event|
        begin
          message = JSON.parse(event.data)
          settings.chat_server.handle_message(client_id, message)
        rescue JSON::ParserError => e
          puts "Invalid JSON received: #{e.message}"
        end
      end

      ws.on :close do |event|
        settings.chat_server.remove_client(client_id)
        ws = nil
      end

      ws.rack_response
    else
      @messages = @room.messages.recent.limit(50)
      erb :chat
    end
  end
end
```

Frontend JavaScript for the chat:

```javascript
// public/js/chat.js
class ChatClient {
  constructor(roomId, userId) {
    this.roomId = roomId;
    this.userId = userId;
    this.ws = null;
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = 5;
    this.typingTimer = null;
    
    this.connect();
    this.bindEvents();
  }
  
  connect() {
    const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const url = `${protocol}//${location.host}/chat/${this.roomId}`;
    
    this.ws = new WebSocket(url);
    
    this.ws.onopen = () => {
      console.log('Connected to chat');
      this.reconnectAttempts = 0;
      this.showConnectionStatus('connected');
    };
    
    this.ws.onmessage = (event) => {
      const message = JSON.parse(event.data);
      this.handleMessage(message);
    };
    
    this.ws.onclose = () => {
      console.log('Disconnected from chat');
      this.showConnectionStatus('disconnected');
      this.attemptReconnect();
    };
    
    this.ws.onerror = (error) => {
      console.error('WebSocket error:', error);
      this.showConnectionStatus('error');
    };
  }
  
  handleMessage(message) {
    switch (message.type) {
      case 'new_message':
        this.displayMessage(message);
        break;
      case 'user_joined':
        this.showUserJoined(message);
        break;
      case 'user_left':
        this.showUserLeft(message);
        break;
      case 'typing_indicator':
        this.handleTypingIndicator(message);
        break;
    }
  }
  
  sendMessage(content, type = 'text') {
    if (this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({
        type: 'chat_message',
        content: content,
        message_type: type
      }));
    }
  }
  
  displayMessage(message) {
    const messagesContainer = document.getElementById('messages');
    const messageElement = document.createElement('div');
    messageElement.className = 'message';
    messageElement.innerHTML = `
      <div class="message-header">
        <span class="user-name">${message.user_name}</span>
        <span class="timestamp">${this.formatTimestamp(message.timestamp)}</span>
      </div>
      <div class="message-content">${this.escapeHtml(message.content)}</div>
    `;
    
    messagesContainer.appendChild(messageElement);
    messagesContainer.scrollTop = messagesContainer.scrollHeight;
  }
  
  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }
  
  formatTimestamp(timestamp) {
    return new Date(timestamp * 1000).toLocaleTimeString();
  }
}
```

## Ajax and CORS

For traditional Ajax requests, you'll need proper CORS handling for cross-origin requests:

```ruby
# lib/cors_helper.rb
module CorsHelper
  def enable_cors(origins = '*', methods = 'GET,POST,PUT,DELETE', allowed_headers = '*')
    headers 'Access-Control-Allow-Origin' => origins
    headers 'Access-Control-Allow-Methods' => methods
    headers 'Access-Control-Allow-Headers' => allowed_headers
    headers 'Access-Control-Max-Age' => '86400'
  end
  
  def handle_preflight
    if request.request_method == 'OPTIONS'
      enable_cors
      halt 200
    end
  end
end

# app.rb
class App < Sinatra::Base
  helpers CorsHelper
  
  before do
    handle_preflight
  end
  
  # API endpoint with CORS
  get '/api/courses' do
    enable_cors
    content_type :json
    
    courses = Course.published.limit(20)
    courses.map(&:to_api_hash).to_json
  end
  
  post '/api/courses/:id/enroll' do
    enable_cors
    content_type :json
    
    course = Course.find(params[:id])
    enrollment = current_user.enroll_in(course)
    
    if enrollment.persisted?
      status 201
      enrollment.to_api_hash.to_json
    else
      status 422
      { errors: enrollment.errors.full_messages }.to_json
    end
  end
end
```

## Embeddable JavaScript Applications with CORS

Create embeddable widgets that work across domains:

```ruby
# Widget endpoint
get '/widgets/course_catalog.js' do
  content_type 'application/javascript'
  
  # Allow embedding from any domain
  enable_cors
  
  erb :course_catalog_widget, layout: false
end
```

Widget template (course_catalog_widget.erb):

```erb
(function() {
  // Avoid conflicts with existing code
  var CourseWidget = {
    apiBase: '<%= request.base_url %>/api',
    
    init: function(containerId, options) {
      this.container = document.getElementById(containerId);
      this.options = options || {};
      this.loadCourses();
    },
    
    loadCourses: function() {
      var xhr = new XMLHttpRequest();
      xhr.open('GET', this.apiBase + '/courses');
      xhr.onload = function() {
        if (xhr.status === 200) {
          var courses = JSON.parse(xhr.responseText);
          CourseWidget.renderCourses(courses);
        }
      };
      xhr.send();
    },
    
    renderCourses: function(courses) {
      var html = '<div class="course-widget">';
      courses.forEach(function(course) {
        html += '<div class="course-item">';
        html += '<h3>' + course.title + '</h3>';
        html += '<p>' + course.description + '</p>';
        html += '<button onclick="CourseWidget.enrollInCourse(' + course.id + ')">Enroll</button>';
        html += '</div>';
      });
      html += '</div>';
      
      this.container.innerHTML = html;
    },
    
    enrollInCourse: function(courseId) {
      // Handle enrollment
      window.open('<%= request.base_url %>/courses/' + courseId, '_blank');
    }
  };
  
  // Expose globally
  window.CourseWidget = CourseWidget;
})();
```

Usage on external sites:

```html
<div id="course-widget"></div>
<script src="https://yoursite.com/widgets/course_catalog.js"></script>
<script>
  CourseWidget.init('course-widget', {
    category: 'programming',
    limit: 5
  });
</script>
```

## Realtime Remote Exception Tracking System

Build your own error tracking system using WebSockets:

```ruby
# lib/exception_tracker.rb
class ExceptionTracker
  def initialize
    @clients = Set.new
  end
  
  def add_client(websocket)
    @clients << websocket
  end
  
  def remove_client(websocket)
    @clients.delete(websocket)
  end
  
  def track_exception(exception, context = {})
    error_data = {
      type: 'exception',
      message: exception.message,
      backtrace: exception.backtrace.first(10),
      context: context,
      timestamp: Time.now.to_i,
      id: SecureRandom.uuid
    }
    
    # Save to database
    ErrorLog.create!(error_data)
    
    # Broadcast to connected dashboards
    broadcast_error(error_data)
    
    # Send to external services (Slack, email, etc.)
    notify_external_services(error_data)
  end
  
  private
  
  def broadcast_error(error_data)
    message = error_data.to_json
    
    @clients.each do |ws|
      begin
        ws.send(message)
      rescue => e
        @clients.delete(ws)
      end
    end
  end
  
  def notify_external_services(error_data)
    # Send to Slack
    notifier = Slack::Notifier.new(ENV['SLACK_WEBHOOK_URL'])
    notifier.ping("New error: #{error_data[:message]}")
    
    # Send critical errors via email
    if error_data[:context][:severity] == 'critical'
      AdminMailer.critical_error(error_data).deliver_now
    end
  end
end

# app.rb
class App < Sinatra::Base
  configure do
    set :exception_tracker, ExceptionTracker.new
  end
  
  # Error handling
  error do
    error_info = env['sinatra.error']
    
    settings.exception_tracker.track_exception(error_info, {
      url: request.url,
      method: request.request_method,
      user_agent: request.user_agent,
      user_id: session[:user_id],
      severity: determine_severity(error_info)
    })
    
    status 500
    'Internal Server Error'
  end
  
  # Dashboard for monitoring errors
  get '/admin/errors' do
    if Faye::WebSocket.websocket?(env)
      ws = Faye::WebSocket.new(env)

      ws.on :open do |event|
        settings.exception_tracker.add_client(ws)
      end

      ws.on :close do |event|
        settings.exception_tracker.remove_client(ws)
        ws = nil
      end

      ws.rack_response
    else
      @recent_errors = ErrorLog.recent.limit(50)
      erb :'admin/errors'
    end
  end
  
  private
  
  def determine_severity(error)
    case error.class.name
    when 'NoMethodError', 'NameError'
      'critical'
    when 'ArgumentError', 'TypeError'
      'high'
    else
      'medium'
    end
  end
end
```

## Creating a Realtime Bidding Application

Here's a real-time auction/bidding system:

```ruby
# lib/auction_server.rb
class AuctionServer
  def initialize
    @auctions = {}
    @clients = {}
  end
  
  def join_auction(auction_id, client_id, websocket, user_id)
    @auctions[auction_id] ||= {
      clients: Set.new,
      current_bid: 0,
      highest_bidder: nil
    }
    
    @clients[client_id] = {
      websocket: websocket,
      user_id: user_id,
      auction_id: auction_id
    }
    
    @auctions[auction_id][:clients] << client_id
    
    # Send current auction state
    auction = Auction.find(auction_id)
    websocket.send({
      type: 'auction_state',
      current_bid: auction.current_bid,
      highest_bidder: auction.highest_bidder&.name,
      time_remaining: auction.time_remaining,
      bid_increment: auction.bid_increment
    }.to_json)
  end
  
  def place_bid(client_id, bid_amount)
    return unless client = @clients[client_id]
    
    auction_id = client[:auction_id]
    user_id = client[:user_id]
    
    auction = Auction.find(auction_id)
    
    if auction.can_bid?(user_id, bid_amount)
      auction.place_bid!(user_id, bid_amount)
      
      broadcast_to_auction(auction_id, {
        type: 'new_bid',
        bid_amount: bid_amount,
        bidder_name: User.find(user_id).name,
        time_remaining: auction.time_remaining
      })
    else
      client[:websocket].send({
        type: 'bid_error',
        message: 'Invalid bid amount'
      }.to_json)
    end
  end
  
  def end_auction(auction_id)
    return unless auction_data = @auctions[auction_id]
    
    auction = Auction.find(auction_id)
    winner = auction.winner
    
    broadcast_to_auction(auction_id, {
      type: 'auction_ended',
      winner: winner&.name,
      winning_bid: auction.current_bid
    })
    
    # Clean up
    auction_data[:clients].each { |client_id| @clients.delete(client_id) }
    @auctions.delete(auction_id)
  end
  
  private
  
  def broadcast_to_auction(auction_id, message)
    return unless auction_data = @auctions[auction_id]
    
    auction_data[:clients].each do |client_id|
      next unless client = @clients[client_id]
      
      begin
        client[:websocket].send(message.to_json)
      rescue => e
        leave_auction(client_id)
      end
    end
  end
end
```

That covers the essential real-time features you can build with Sinatra. WebSockets open up a world of possibilities for creating engaging, interactive applications. Start with the basics and gradually add complexity as your requirements grow. The key is to handle edge cases like connection drops, reconnection logic, and proper error handling to create robust real-time experiences.
