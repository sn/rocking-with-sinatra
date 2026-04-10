# Chapter 3 - Templates, Partials, Layouts & Emails

When it comes to markup, as with everything else, Sinatra let’s you write things the way you want to. If you wish to render HTML using HAML, that’s perfectly acceptable. Sinatra supports quite a few [template rendering engines] out the box and you can add your own if required, but sticking with [ERB] is generally a good idea unless you require another renderer for special circumstances.

However, with great freedom comes a long rope to hang yourself - planning your directory structures, layouts, views & partials will become crucial to creating maintainable software.

Unlike Rails, you don’t get a default project structure when you create a new Sinatra project - you get a blank slate. There are [3rd-party scaffold generators](http://c7.github.io/hazel/) available to try, but I’ve rarely found them useful myself. Most Sinatra developers prefer to create their own reliable ground work to build their apps from and you should focus on doing the same.

The views could also be directly embedded into your Sinatra app file as **inline views**, but please don’t do that unless the world is ending or you really have to. An exception to the rule would be when your app is distributed as a stand-alone gem or being tacked onto another app where it sometimes doesn’t make sense to have it’s own ‘views’ directory.

Rails developers usually quickly notice the lack of support for partial views in Sinatra, but that’s an easy fix and I’ll show you the helper method I add to projects as part of my set up.

We’ll start by setting up the basic outline for your app. You can choose to go with either the classic style app or a modular app for this, but I will be using modular style from here on out unless explicitly stated otherwise.

#### Default Classic Style Structure Example

```
app.rb
config.ru
Gemfile
config
   development.rb
   production.rb
   testing.rb
spec
	app_spec.rb
public
	css
		site.css
	img
	js
		app.js
views
	pages
		home.erb
	layouts
		website.erb
```

#### Default Modular Style Structure Example

```
 app.rb
config.ru
Gemfile
config
   development.rb
   production.rb
   testing.rb
controllers
   init.rb
models
   init.rb
helpers
   init.rb
spec
	app_spec.rb
public
	css
		app.css
	img
	js
		app.js
views
	pages
		home.erb
	layouts
		website.erb
```

As you’ll notice, the modular style example contains more directories than the classic style version. In most cases, I like organizing my code according to the MVC pattern to start out with. The controllers, models & helpers directories should give you the hint of whats to come if you are familiar with the MVC pattern.

If you prefer software architecture patterns other than MVC, feel free to arrange your project accordingly.

We'll take the **modular style app** forward in this chapter and start by adding our default settings, helpers, routes & assets in a way that lends itself to a maintainable codebase later down the line when the app grows in size.

##### Differences Between Views, Layouts & Partials

If you are not very familiar with Sinatra, you are probably wondering what the difference is between views & layouts.

**Layouts**

The master containers that give you a page structure to work with. Sinatra injects your page content into your layouts.

You don’t want to create an entire HTML document from scratch each time you create a new page, so you’ll put the header, meta tags, menu & footer into a layout and dynamically load the body content into it for each page when it’s rendered.

A common use-case is to create distinct layouts for mobile or desktop versions of you site or application if you do not plan on employing responsive design. Please use a responsive design approach ;)

**Views**

Views are the stand-alone pieces of content or pages that get dynamically loaded into layouts. A view can be a simple blog post, image gallery, product description or entire page.

A view can also explicitly be rendered on it’s own without a layout from within your Ruby code and re-used elsewhere.

Note that in some of the available Sinatra resources online, the words ‘views’ & ‘templates’ are used interchangeably, but the correct word here is **“view”** and that’s what we’ll be using throughout this book.

**Partials**

Partials are small re-usable fragments of views that can easily be embedded in a view or layout. They generally don't have logic or need for data, but usually consist of:

* Navigational Elements
* Google Analytics or other tracking code
* Form feedback (Flash messages)
* Conditional scripting or CSS

##### Adding Support for Partial Views

Since Sinatra doesn't have support for partials out of the box, let's add it with a simple helper.

Open up **app.rb** and make sure it looks like this:

```ruby
require 'sinatra/base'

class App < Sinatra::Base

  configure :development do
	set :dump_errors , true
	set :logging     , true
	set :raise_errors, true
  end

  configure :production do
	set :dump_errors , false
	set :logging     , false
	set :raise_errors, true
  end

  configure do
	set :root          , File.dirname(__FILE__)
	set :public_folder , File.dirname(__FILE__) + '/public'
	set :app_file      , __FILE__
	set :views         , File.dirname(__FILE__) + '/views'
	set :tests         , File.dirname(__FILE__) + ‘/spec’    
	set :show_exceptions, development?
  end

  helpers do
	def partial(template, locals = {})
	  begin
		locals = locals.to_hash if !locals.is_a?(Hash)
	  rescue NoMethodError => e
		locals = {}
	  end

	  parts = template.split('/')
  
	  parts << "_#{parts.pop}"
  
	  erb(parts.join('/').to_sym, layout: false, locals: locals)
	end
  end
end
```

Firstly, we use 3 different configuration blocks to set default app config values in development, production and a catch-all block for all environments. Usually, you would add a configuration block for a `:testing` environment, but I’ve left it out here for the sake of brevity.

Next, we define a simple helper method `partial(template, locals = {})` that you will use inside your views to render the partials. This should be defined in the Sinatra `helpers` block.

Partials in Rails start with underscores, so we’ll do the same here for our Rails friends.

The partial `_file.erb` can live anywhere within your app’s `views` directory which you set in the above configure block.

Next, let's create the general HTML page layout for our example and inject a partial into it using our newly created helper method:

_views/pages/home.erb_

```erb
<html>
  <head>
	<title>Partial Example</title>
  </head>
  <body>
	<%= partial “pages/home”  %>  
  </body>
</html>
```

You can also pass local variables as a hash to the partial method that in-turn will make them available to the view as instance variables:

_views/pages/products.erb_

```erb
<html>
  <head>
	<title>Partial Example</title>
  </head>
  <body>
	<% @products.each do |p| %>
	  <%= partial “products/item”, {:product => p}  %>  
	<% end %>
  </body>
</html>
```

_views/partials/_product.erb_

```erb
<div class=“product”>
  <h2>
	<%= product.name %>
  </h2>
  <p>
	<%= product.description %>
  </p>
  <a href=“#” title=“Buy Now”>$<%= product.price %> - Buy Now</a>
</div>
```

Notice that in the above code, we have access to the local variable `product` that was passed into the `partial()` method’s second parameter.

##### Defining & Using Page Layouts

In larger applications, you will probably need more than one layout, but keep in mind that creating layouts can quickly get out of hand if you are not careful.

The most important thing about working with layouts is naming them logically to tie back to the areas in your code where they're used.

As an example, can you figure out which one of these layouts are for the actual modal dialog that pops up when a user clicks modal link on a page?

* `views/layouts/popup.erb`
* `views/layouts/dialog.erb`

In this case, `popup.erb` would be loaded when the modal window is loaded and `dialog.erb` is used for single page dialogs that don’t contain footers or headers - this is a good example of how not to do it.

Figure out a consistent formula for naming layouts early on to save yourself & fellow programmers a lot of frustration later down the line.

A better naming solution for the above layouts would be:

* `views/layouts/modal-popup.erb`
* `views/layouts/dialog-window.erb`

To use the layout in your route handlers, you will need to

###### Creating Our Website Layout File

Open up `views/layouts/website.erb` and add the following code:

```erb
 <html>
  <head>
	<title>Website Layout Example</title>
  </head>
  <body>
	<%= yield %>
  </body>
</html>
```

Next, open up `views/pages/home.erb` and add this code to it:

```ruby
<h1>Home Page</h1>
<p>
  This is the home page that we’ll extend later.
</p>
```

Lastly, to render the page content inside the layout with ERB, we will use the following Ruby code in your route handler:

```ruby
get ‘/home’ do
   erb :”pages/home”, :layout => :”layouts/website”
end
```

We can easily re-use the layout for other pages that have the same visual layout requirements:

```ruby
get ‘/product/id?’ do
   @products = Product.all
   erb :”pages/products”, :layout => :”layouts/website”
end
```

##### Variable Scope inside Layouts & Views

Views are evaluated and rendered within the context of a block inside the context of the calling method.

This means that all instance variables available to the top level block will be available inside your views as instance variables.

Let’s explain the above with pseudo-code:

```ruby
 get '/' do
  @title = "My Page Title"

  erb :"pages/home", :layout => :"layouts/website", :locals => {:foo => "bar"}
 end
```

The instance variable @title will be available within the layout, view and partials that are rendered from this block.

`:foo` will be available as `foo` in the layout, views and partials.

##### Effectively dealing with Mailers

Mailers should be thought of as views primarily because they consist of text or HTML content being sent to the end user.

If you use mailers as views, it means that you are free to mix in partials or layouts as needed.

Leaving the loading, parsing and variable assignment up to Sinatra will make life a bit easier for you - especially when your client wants to tweak the mailer templates :)

Start by creating a `views/mailers` directory in your project and add a layout file called `layouts/mailer.erb`.

A good naming convention here is important just as it is with the rest of your views, templates and partials.

Here's a practical example of setting up email layouts and templates:

_views/layouts/mailer.erb_

```erb
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background-color: #2c3e50; color: white; padding: 20px; text-align: center; }
    .content { padding: 20px; background-color: #f9f9f9; }
    .footer { text-align: center; padding: 20px; color: #666; font-size: 0.9em; }
    .button { display: inline-block; padding: 10px 20px; background-color: #3498db; color: white; text-decoration: none; border-radius: 4px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>LearnHub</h1>
    </div>
    <div class="content">
      <%= yield %>
    </div>
    <div class="footer">
      <p>&copy; <%= Date.today.year %> LearnHub. All rights reserved.</p>
      <p>
        <a href="<%= @unsubscribe_url %>">Unsubscribe</a> | 
        <a href="<%= @preferences_url %>">Email Preferences</a>
      </p>
    </div>
  </div>
</body>
</html>
```

_views/mailers/welcome.erb_

```erb
<h2>Welcome to LearnHub, <%= @user.first_name %>!</h2>

<p>Thanks for joining our learning community. We're excited to have you on board!</p>

<p>Here's what you can do next:</p>

<ul>
  <li>Browse our <a href="<%= @courses_url %>">course catalog</a></li>
  <li>Complete your <a href="<%= @profile_url %>">profile</a></li>
  <li>Join our <a href="<%= @community_url %>">community forums</a></li>
</ul>

<p style="text-align: center; margin-top: 30px;">
  <a href="<%= @browse_url %>" class="button">Start Learning</a>
</p>

<p>If you have any questions, just reply to this email!</p>

<p>Happy learning,<br>
The LearnHub Team</p>
```

Now let's create a mailer helper to send these emails:

_helpers/mailer_helper.rb_

```ruby
module MailerHelper
  def send_welcome_email(user)
    @user = user
    @courses_url = "#{settings.base_url}/courses"
    @profile_url = "#{settings.base_url}/profile"
    @community_url = "#{settings.base_url}/community"
    @browse_url = "#{settings.base_url}/courses"
    @unsubscribe_url = "#{settings.base_url}/unsubscribe/#{user.unsubscribe_token}"
    @preferences_url = "#{settings.base_url}/preferences"
    
    subject = "Welcome to LearnHub!"
    html_body = erb(:"mailers/welcome", :layout => :"layouts/mailer")
    
    send_email(
      to: user.email,
      subject: subject,
      html_body: html_body
    )
  end
  
  def send_enrollment_confirmation(enrollment)
    @user = enrollment.user
    @course = enrollment.course
    @start_learning_url = "#{settings.base_url}/learn/#{@course.slug}"
    @unsubscribe_url = "#{settings.base_url}/unsubscribe/#{@user.unsubscribe_token}"
    @preferences_url = "#{settings.base_url}/preferences"
    
    subject = "You're enrolled in #{@course.title}!"
    html_body = erb(:"mailers/enrollment_confirmation", :layout => :"layouts/mailer")
    
    send_email(
      to: @user.email,
      subject: subject,
      html_body: html_body
    )
  end
  
  private
  
  def send_email(to:, subject:, html_body:, text_body: nil)
    from_address = settings.email_from
    Mail.deliver do
      from     from_address
      to       to
      subject  subject
      
      html_part do
        content_type 'text/html; charset=UTF-8'
        body html_body
      end
      
      if text_body
        text_part do
          body text_body
        end
      end
    end
  end
end
```

## Using the Mail Gem for Email Delivery

The Mail gem is a fantastic choice for Sinatra applications. It's lightweight and doesn't require Rails:

_Gemfile_

```ruby
gem 'mail'
gem 'premailer' # For CSS inlining
```

_config/mail.rb_

```ruby
require 'mail'
require 'premailer'

Mail.defaults do
  delivery_method :smtp, {
    :address => ENV['SMTP_SERVER'],
    :port => ENV['SMTP_PORT'] || 587,
    :domain => ENV['SMTP_DOMAIN'],
    :user_name => ENV['SMTP_USERNAME'],
    :password => ENV['SMTP_PASSWORD'],
    :authentication => :plain,
    :enable_starttls_auto => true
  }
end

# Development configuration
if ENV['RACK_ENV'] == 'development'
  Mail.defaults do
    delivery_method :file, location: File.expand_path('../../tmp/mails', __FILE__)
  end
end

# Test configuration
if ENV['RACK_ENV'] == 'test'
  Mail.defaults do
    delivery_method :test
  end
end
```

## Testing Your Mailers with Letter Opener

During development, you want to see your emails without actually sending them:

_Gemfile_

```ruby
group :development do
  gem 'letter_opener'
end
```

_config/mail.rb_

```ruby
configure :development do
  require 'letter_opener'
  
  Mail.defaults do
    delivery_method LetterOpener::DeliveryMethod, 
      :location => File.expand_path('../../tmp/letter_opener', __FILE__)
  end
end
```

Now when you send an email in development, it opens in your browser instead!

## Using ActionMailer to Send Emails

If you need more advanced features, you can integrate ActionMailer without Rails:

_Gemfile_

```ruby
gem 'actionmailer', '~> 6.1'
```

_config/action_mailer.rb_

```ruby
require 'action_mailer'

# Configure ActionMailer
ActionMailer::Base.raise_delivery_errors = true
ActionMailer::Base.delivery_method = :smtp
ActionMailer::Base.view_paths = File.expand_path('../../views', __FILE__)
ActionMailer::Base.smtp_settings = {
  :address => ENV['SMTP_SERVER'],
  :port => ENV['SMTP_PORT'],
  :domain => ENV['SMTP_DOMAIN'],
  :user_name => ENV['SMTP_USERNAME'],
  :password => ENV['SMTP_PASSWORD'],
  :authentication => :plain,
  :enable_starttls_auto => true
}

# Base mailer class
class ApplicationMailer < ActionMailer::Base
  default from: ENV['EMAIL_FROM'] || 'noreply@learnhub.com'
  layout 'mailer'
end
```

_mailers/user_mailer.rb_

```ruby
class UserMailer < ApplicationMailer
  def welcome(user)
    @user = user
    @courses_url = "#{ENV['BASE_URL']}/courses"
    @profile_url = "#{ENV['BASE_URL']}/profile"
    
    mail(
      to: @user.email,
      subject: 'Welcome to LearnHub!'
    )
  end
  
  def enrollment_confirmation(enrollment)
    @enrollment = enrollment
    @user = enrollment.user
    @course = enrollment.course
    
    mail(
      to: @user.email,
      subject: "You're enrolled in #{@course.title}!"
    )
  end
  
  def password_reset(user, reset_token)
    @user = user
    @reset_url = "#{ENV['BASE_URL']}/password/reset?token=#{reset_token}"
    
    mail(
      to: @user.email,
      subject: 'Reset your password'
    )
  end
end
```

Using ActionMailer in your routes:

```ruby
post '/users' do
  @user = User.create!(params[:user])
  
  # Send welcome email
  UserMailer.welcome(@user).deliver_now
  
  redirect '/dashboard'
end

post '/courses/:id/enroll' do
  @course = Course.find(params[:id])
  @enrollment = current_user.enroll_in(@course)
  
  # Send confirmation
  UserMailer.enrollment_confirmation(@enrollment).deliver_now
  
  redirect "/courses/#{@course.id}"
end
```

## Email Best Practices

### 1. Use Background Jobs for Email Delivery

Don't make users wait for emails to send:

_Gemfile_

```ruby
gem 'sidekiq'
```

_workers/email_worker.rb_

```ruby
class EmailWorker
  include Sidekiq::Worker
  
  def perform(mailer_class, mailer_method, *args)
    mailer = mailer_class.constantize
    email = mailer.send(mailer_method, *args)
    email.deliver_now
  end
end
```

_helpers/email_helper.rb_

```ruby
module EmailHelper
  def send_email_async(mailer_class, mailer_method, *args)
    EmailWorker.perform_async(mailer_class.to_s, mailer_method.to_s, *args)
  end
end

# Usage:
# send_email_async(UserMailer, :welcome, user.id)
```

### 2. Handle Bounces and Complaints

```ruby
post '/webhooks/email/bounce' do
  # Verify webhook authenticity
  signature = request.env['HTTP_X_WEBHOOK_SIGNATURE']
  unless valid_webhook_signature?(signature, request.body.read)
    halt 401, "Unauthorized"
  end
  
  bounce_data = JSON.parse(request.body.read)
  email = bounce_data['email']
  
  # Mark email as bounced
  user = User.find_by_email(email)
  user.update(email_bounced: true) if user
  
  status 200
end
```

### 3. Track Email Opens and Clicks

```ruby
get '/track/open/:token' do
  tracking = EmailTracking.find_by_token(params[:token])
  tracking.record_open! if tracking
  
  # Return 1x1 transparent pixel
  content_type 'image/gif'
  send_file 'public/images/pixel.gif'
end

get '/track/click/:token' do
  tracking = ClickTracking.find_by_token(params[:token])
  
  if tracking
    tracking.record_click!
    redirect tracking.destination_url
  else
    redirect '/'
  end
end
```

### 4. CSS Inlining for Better Email Client Support

```ruby
helpers do
  def inline_css_for_email(html)
    premailer = Premailer.new(
      html,
      :with_html_string => true,
      :css_to_attributes => true
    )
    premailer.to_inline_css
  end
end
```

## Advanced Templating Techniques

### Content Blocks

Similar to Rails' content_for:

```ruby
helpers do
  def content_for(key, content = nil)
    @content_blocks ||= {}
    if content
      @content_blocks[key] = content
    else
      @content_blocks[key]
    end
  end
  
  def yield_content(key)
    content_for(key)
  end
end
```

Usage in views:

```erb
<% content_for :head do %>
  <meta property="og:title" content="<%= @course.title %>">
  <link rel="stylesheet" href="/css/course.css">
<% end %>

<% content_for :scripts do %>
  <script src="/js/video-player.js"></script>
<% end %>
```

In layout:

```erb
<head>
  <title>LearnHub</title>
  <%= yield_content :head %>
</head>
<body>
  <%= yield %>
  
  <script src="/js/app.js"></script>
  <%= yield_content :scripts %>
</body>
```

### Template Caching

Sinatra automatically caches compiled templates in production, so there's no extra setup needed for that. But you can add your own fragment caching for expensive partials:

helpers do
  def cached_partial(key, ttl = 3600, &block)
    if settings.production?
      cache_key = "partial:#{key}"
      cached = settings.cache.get(cache_key)
      
      return cached if cached
      
      content = capture(&block)
      settings.cache.set(cache_key, content, ttl)
      content
    else
      capture(&block)
    end
  end
end
```

That covers the essentials of working with templates, layouts, and emails in Sinatra. The key is starting simple and adding complexity only as needed. With these patterns, you can build everything from basic websites to sophisticated applications with rich email communications.
