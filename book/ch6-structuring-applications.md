# Chapter 6 - Structuring Your Applications

Sinatra's blank slate is its biggest selling point - and, if you're not careful, its biggest trap. I've seen developers start with one `app.rb` that works beautifully at 50 lines and then spend weeks trying to untangle the same file once it hits 2,000. The framework isn't going to save you from that. It's entirely up to you to impose structure before you need it, not after.

I found it much easier to think about Sinatra application structure as a separate concern from Sinatra itself. The framework gives you the routing DSL & the request/response lifecycle. Everything around that - how you organize files, how you wire in helpers, how you separate configuration from business logic - that's all on you. Once I accepted that, structuring Sinatra apps became something I actually enjoyed rather than resented.

Throughout this chapter we'll use our course marketplace, LearnHub, as the running example. It's grown just enough to make structure matter.

## MVC & Directory Structure

If you've ever built a Rails app, MVC is already familiar territory. If not, I would recommend reading up a bit more on MVC & other architectural patterns before going too far - understanding it well makes everything else in this chapter click into place. The basic idea is that your application splits its responsibilities across three layers: Models handle your data & business logic, Views produce the HTML your users see, and Controllers sit in the middle routing requests to the right model & view.

Sinatra doesn't give you MVC out of the box, but it doesn't get in the way of it either. Here's how the mapping looks in practice:

- **Models** - Ruby classes (usually backed by ActiveRecord) that represent your data and business logic. Lives in `models/`.
- **Views** - ERB templates that produce HTML. Lives in `views/`.
- **Controllers** - In Sinatra, these are files full of route definitions grouped by concern. Lives in `controllers/`.

Everything else - shared libraries, configuration, initializers - has a home too. Here's the directory structure I'd use for the course marketplace:

```
learnhub/
├── app.rb                  # Main application class, wires everything together
├── config.ru               # Rack entry point
├── Gemfile
├── Gemfile.lock
├── Rakefile
├── .env                    # Environment variables (never commit this)
├── .env.example            # Template for .env (safe to commit)
├── .rubocop.yml
│
├── config/
│   ├── application.rb      # App-wide configuration
│   ├── database.yml        # Database connection settings
│   └── initializers/
│       ├── database.rb     # ActiveRecord connection setup
│       ├── redis.rb        # Redis connection
│       └── logging.rb      # Logger configuration
│
├── controllers/
│   ├── base_controller.rb  # Shared controller functionality
│   ├── courses.rb          # Course browsing routes
│   ├── enrollment.rb       # Enrollment and checkout routes
│   ├── instructor.rb       # Instructor dashboard routes
│   ├── sessions.rb         # Login/logout routes
│   └── api/
│       ├── v1/
│       │   └── courses.rb
│       └── v2/
│           └── courses.rb
│
├── models/
│   ├── concerns/
│   │   ├── sluggable.rb    # Shared slug generation logic
│   │   └── priceable.rb    # Shared pricing/currency logic
│   ├── user.rb
│   ├── course.rb
│   ├── lesson.rb
│   ├── enrollment.rb
│   └── review.rb
│
├── helpers/
│   ├── auth_helper.rb
│   ├── view_helper.rb
│   └── flash_helper.rb
│
├── lib/
│   ├── extensions/
│   │   └── request_timer.rb  # Custom Sinatra extensions
│   └── services/
│       ├── payment_processor.rb
│       └── email_sender.rb
│
├── db/
│   ├── migrations/
│   └── seeds.rb
│
├── public/
│   ├── css/
│   ├── js/
│   └── images/
│
├── views/
│   ├── layouts/
│   │   ├── application.erb
│   │   └── instructor.erb
│   ├── courses/
│   │   ├── index.erb
│   │   ├── show.erb
│   │   └── player.erb
│   ├── instructor/
│   │   ├── dashboard.erb
│   │   └── course_form.erb
│   ├── sessions/
│   │   └── new.erb
│   └── partials/
│       ├── _nav.erb
│       ├── _course_card.erb
│       └── _flash.erb
│
└── spec/
    ├── spec_helper.rb
    ├── models/
    └── controllers/
```

That looks like a lot at first glance, but you don't create all of that on day one - you grow into it. Start with `app.rb`, `config.ru`, and the `models/`, `views/`, and `controllers/` directories. Add the rest when you actually need it.

The whole point is that anyone picking up this codebase - including yourself three months from now - should be able to look at the directory tree and immediately know where things live. Bug in course pricing? Open `models/course.rb`. Checkout page rendering wrong? `views/courses/` and `controllers/enrollment.rb`. No hunting required, no tribal knowledge needed.

## Helpers

Helpers are methods you want available inside route handlers and inside ERB views. Sinatra gives you a `helpers` block to define them, which is one of those small features that quietly saves you a lot of repeated code.

The simplest form is to define helpers inline in your app class - let's take a look:

```ruby
class App < Sinatra::Base
  helpers do
    def current_user
      @current_user ||= User.find(session[:user_id]) if session[:user_id]
    end

    def logged_in?
      !current_user.nil?
    end
  end

  get '/dashboard' do
    redirect '/login' unless logged_in?
    @courses = current_user.enrolled_courses
    erb :'dashboard/index'
  end
end
```

Inline helpers work well for small apps, but once you have more than a handful of helper methods it gets cluttered fast. I generally move helpers out into modules as soon as there are enough of them to justify it - here's how that looks:

```ruby
# helpers/auth_helper.rb
module AuthHelper
  def current_user
    @current_user ||= User.find(session[:user_id]) if session[:user_id]
  end

  def logged_in?
    !current_user.nil?
  end

  def require_login!
    unless logged_in?
      session[:return_to] = request.fullpath
      redirect '/login'
    end
  end

  def require_instructor!
    require_login!
    halt 403, erb(:'errors/403') unless current_user.instructor?
  end
end
```

```ruby
# app.rb
require_relative 'helpers/auth_helper'

class App < Sinatra::Base
  helpers AuthHelper

  get '/instructor/dashboard' do
    require_instructor!
    @courses = current_user.courses
    erb :'instructor/dashboard'
  end
end
```

The `helpers` method accepts both a block and module names - you can mix and match as needed:

```ruby
class App < Sinatra::Base
  helpers AuthHelper
  helpers ViewHelper
  helpers FlashHelper

  helpers do
    # One-off helper that doesn't warrant its own module
    def app_name
      settings.app_name
    end
  end
end
```

Methods defined in helper modules are available in both route handlers and ERB templates automatically. That's the real value - you define `current_user` once and it works everywhere without any extra wiring.

## Settings / Configuration

Sinatra's `configure` block is how you set application-wide options. It accepts an environment name or runs for all environments - here's a configuration setup I'd use as a starting point:

```ruby
class App < Sinatra::Base
  # Runs in every environment
  configure do
    set :app_name, 'LearnHub'
    set :sessions, true
    set :session_secret, ENV.fetch('SESSION_SECRET')
    set :views, File.join(root, 'views')
    set :public_folder, File.join(root, 'public')
  end

  # Only in development
  configure :development do
    set :logging, true
    set :dump_errors, true
    set :show_exceptions, true
  end

  # Only in production
  configure :production do
    set :logging, false
    set :dump_errors, false
    set :show_exceptions, false
    disable :raise_errors
  end
end
```

`settings` gives you back those values anywhere in your app - routes, helpers, wherever you need them:

```ruby
get '/about' do
  @app_name = settings.app_name
  erb :about
end
```

For anything beyond simple flags & strings, environment variables are the right tool. I can't stress this enough - never hardcode secrets, database URLs, API keys, or anything environment-specific into source code. It always comes back to bite you.

The `dotenv` gem makes this painless during development:

```ruby
# Gemfile
gem 'dotenv'
```

```bash
# .env  (never commit this file)
DATABASE_URL=postgres://localhost/learnhub_development
SESSION_SECRET=some_long_random_string_here
STRIPE_SECRET_KEY=sk_test_...
REDIS_URL=redis://localhost:6379/0
```

```bash
# .env.example  (safe to commit - shows what variables are needed)
DATABASE_URL=
SESSION_SECRET=
STRIPE_SECRET_KEY=
REDIS_URL=
```

Load dotenv at the very top of your boot sequence before anything else reads `ENV` - order matters here:

```ruby
# config.ru
require 'dotenv/load'

require_relative 'app'
run App
```

For configuration that's more complex than individual variables, I like wrapping everything in a config module. It gives you a single place to gather all settings with sensible defaults, and it reads much more clearly at the call sites:

```ruby
# config/application.rb
module LearnHub
  module Config
    extend self

    def database_url
      ENV.fetch('DATABASE_URL', 'postgres://localhost/learnhub_development')
    end

    def redis_url
      ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')
    end

    def session_secret
      ENV.fetch('SESSION_SECRET') do
        raise 'SESSION_SECRET environment variable is not set'
      end
    end

    def stripe_secret_key
      ENV.fetch('STRIPE_SECRET_KEY') do
        raise 'STRIPE_SECRET_KEY environment variable is not set'
      end
    end

    def production?
      ENV.fetch('RACK_ENV', 'development') == 'production'
    end

    def development?
      ENV.fetch('RACK_ENV', 'development') == 'development'
    end

    def test?
      ENV.fetch('RACK_ENV', 'development') == 'test'
    end

    def max_upload_size
      (ENV.fetch('MAX_UPLOAD_SIZE', '50')).to_i * 1024 * 1024
    end
  end
end
```

Then use it throughout your app wherever you need configuration values:

```ruby
require_relative 'config/application'

ActiveRecord::Base.establish_connection(LearnHub::Config.database_url)
$redis = Redis.new(url: LearnHub::Config.redis_url)
```

Using `ENV.fetch` instead of `ENV[]` is a habit I picked up early and I've never looked back. `fetch` raises a `KeyError` if the variable is missing, which means you get a clear error at startup rather than a mysterious `nil` that crashes somewhere deep in a request handler an hour later. I can guarantee you that hunting down that kind of bug is not how you want to spend a Tuesday afternoon.

## Application Boot Process

`config.ru` is the file Rack reads when you run `bundle exec rackup` - it's the entry point for your entire application. In a small app it's two lines. Once you're building something production-worthy it needs to do real work in a specific order. Here's the boot sequence I settled on for LearnHub:

```ruby
# config.ru

# Step 1: Load environment variables before anything reads ENV
require 'dotenv/load'

# Step 2: Load Bundler and all gems
require 'bundler/setup'
Bundler.require(:default, ENV.fetch('RACK_ENV', 'development').to_sym)

# Step 3: Load application configuration
require_relative 'config/application'

# Step 4: Load initializers (database, Redis, etc.)
Dir[File.join(__dir__, 'config', 'initializers', '*.rb')].sort.each do |f|
  require f
end

# Step 5: Load models
Dir[File.join(__dir__, 'models', '**', '*.rb')].sort.each do |f|
  require f
end

# Step 6: Load helpers
Dir[File.join(__dir__, 'helpers', '*.rb')].sort.each do |f|
  require f
end

# Step 7: Load the main app and controllers
require_relative 'app'

# Step 8: Run the app
run App
```

Each initializer handles one piece of infrastructure - keeping them separate means you can add, remove, or swap them without touching the rest of your boot sequence. Here's what a real database initializer looks like:

```ruby
# config/initializers/database.rb
require 'active_record'

ActiveRecord::Base.establish_connection(LearnHub::Config.database_url)
ActiveRecord::Base.logger = Logger.new($stdout) if LearnHub::Config.development?

# Raise an error early if the connection doesn't work
begin
  ActiveRecord::Base.connection.execute('SELECT 1')
rescue ActiveRecord::NoDatabaseError => e
  abort "Database connection failed: #{e.message}\nRun: bundle exec rake db:create"
end
```

```ruby
# config/initializers/redis.rb
require 'redis'

$redis = Redis.new(
  url: LearnHub::Config.redis_url,
  connect_timeout: 5,
  read_timeout: 5,
  write_timeout: 5
)

begin
  $redis.ping
rescue Redis::CannotConnectError => e
  abort "Redis connection failed: #{e.message}"
end
```

The sort on the `Dir` glob matters - files load in alphabetical order, which means you can name them `01_database.rb`, `02_redis.rb` if you need explicit control over sequencing. In most cases alphabetical is fine.

Your main `app.rb` then becomes the place where everything gets wired together:

```ruby
# app.rb
require 'sinatra/base'
require_relative 'helpers/auth_helper'
require_relative 'helpers/view_helper'
require_relative 'helpers/flash_helper'
require_relative 'controllers/sessions'
require_relative 'controllers/courses'
require_relative 'controllers/enrollment'
require_relative 'controllers/instructor'

class App < Sinatra::Base
  configure do
    set :app_name, 'LearnHub'
    set :root, File.dirname(__FILE__)
    set :views, File.join(root, 'views')
    set :public_folder, File.join(root, 'public')
    set :sessions, true
    set :session_secret, LearnHub::Config.session_secret
    set :method_override, true   # enables PUT/DELETE from HTML forms
  end

  configure :development do
    set :logging, true  # configure logger level separately via Logger.new if needed
    set :dump_errors, true
    set :show_exceptions, true
  end

  configure :production do
    set :logging, false
    set :dump_errors, false
    set :show_exceptions, false
  end

  helpers AuthHelper
  helpers ViewHelper
  helpers FlashHelper

  use SessionsController
  use CoursesController
  use EnrollmentController
  use InstructorController

  # 404 handler
  not_found do
    erb :'errors/404'
  end

  # 500 handler
  error do
    @error = env['sinatra.error']
    erb :'errors/500'
  end
end
```

Each controller is a class that inherits from a base controller, which itself inherits from `Sinatra::Base`. This is how you split routes across multiple files without repeating common setup code in every single controller:

```ruby
# controllers/base_controller.rb
class BaseController < Sinatra::Base
  configure do
    set :views, File.join(File.dirname(__FILE__), '..', 'views')
  end

  helpers AuthHelper
  helpers ViewHelper
  helpers FlashHelper
end
```

```ruby
# controllers/courses.rb
class CoursesController < BaseController
  get '/courses' do
    @courses = Course.published.order(created_at: :desc)
    erb :'courses/index'
  end

  get '/courses/:slug' do
    @course = Course.find_by_slug!(params[:slug])
    erb :'courses/show'
  end
end
```

## Creating Custom Helpers

Let's build the three helper modules LearnHub actually needs. I'll walk through each one - these form a solid baseline you can adapt to your own projects.

### Authentication Helper

```ruby
# helpers/auth_helper.rb
module AuthHelper
  def current_user
    return nil unless session[:user_id]
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def logged_in?
    !current_user.nil?
  end

  def require_login!
    return if logged_in?

    session[:return_to] = request.fullpath
    flash[:warning] = 'Please log in to continue.'
    redirect '/login'
  end

  def require_instructor!
    require_login!
    unless current_user.instructor?
      halt 403, erb(:'errors/403')
    end
  end

  def require_admin!
    require_login!
    unless current_user.admin?
      halt 403, erb(:'errors/403')
    end
  end

  def login!(user)
    session[:user_id] = user.id
    session[:logged_in_at] = Time.now.to_i
  end

  def logout!
    session.clear
  end

  def enrolled_in?(course)
    return false unless logged_in?
    current_user.enrollments.exists?(course: course)
  end
end
```

Using it in a route is straightforward:

```ruby
get '/my/courses' do
  require_login!
  @enrollments = current_user.enrollments.includes(:course).recent
  erb :'students/my_courses'
end
```

And in a view template, the same helper methods are available without any extra setup:

```erb
<% if logged_in? %>
  <a href="/my/courses">My Courses</a>
<% else %>
  <a href="/login">Log In</a>
<% end %>
```

### View Helpers

View helpers keep logic out of templates. My general rule - if you find yourself writing more than a line or two of Ruby inside `<% %>` tags, that logic belongs in a helper. Templates should read like prose, not like a Ruby script.

```ruby
# helpers/view_helper.rb
module ViewHelper
  # Format a price as currency
  # format_currency(4999)    => "$49.99"
  # format_currency(0)       => "Free"
  def format_currency(cents)
    return 'Free' if cents.zero?

    dollars = cents / 100.0
    "$#{format('%.2f', dollars)}"
  end

  # Human-readable time difference
  # time_ago(10.minutes.ago)  => "10 minutes ago"
  # time_ago(3.days.ago)      => "3 days ago"
  def time_ago(time)
    seconds = (Time.now - time).to_i
    return 'just now' if seconds < 60

    minutes = seconds / 60
    return "#{minutes} minute#{minutes == 1 ? '' : 's'} ago" if minutes < 60

    hours = minutes / 60
    return "#{hours} hour#{hours == 1 ? '' : 's'} ago" if hours < 24

    days = hours / 24
    return "#{days} day#{days == 1 ? '' : 's'} ago" if days < 30

    months = days / 30
    return "#{months} month#{months == 1 ? '' : 's'} ago" if months < 12

    years = days / 365
    "#{years} year#{years == 1 ? '' : 's'} ago"
  end

  # Truncate text with an ellipsis
  def truncate(text, length: 100, omission: '...')
    return text if text.length <= length
    text[0, length - omission.length] + omission
  end

  # Star rating display
  # star_rating(4.5)  => "★★★★½"
  def star_rating(score)
    full_stars  = score.floor
    half_star   = (score - full_stars) >= 0.5
    empty_stars = 5 - full_stars - (half_star ? 1 : 0)

    ('★' * full_stars) +
      (half_star ? '½' : '') +
      ('☆' * empty_stars)
  end

  # Build a CSS class string conditionally
  # css_class('btn', 'btn-primary', active: true, disabled: false)
  # => "btn btn-primary active"
  def css_class(*base_classes, **conditional_classes)
    active = conditional_classes.select { |_, v| v }.keys.map(&:to_s)
    (base_classes.map(&:to_s) + active).join(' ')
  end

  # Simple partial renderer
  def partial(template, locals: {})
    erb :"partials/#{template}", locals: locals, layout: false
  end

  # Page title helper
  def page_title(title = nil)
    if title
      @page_title = title
    else
      [@page_title, settings.app_name].compact.join(' | ')
    end
  end
end
```

In a view template, these helpers read very naturally - which is exactly the point:

```erb
<h2><%= course.title %></h2>
<p><%= truncate(course.description, length: 150) %></p>
<span class="price"><%= format_currency(course.price_cents) %></span>
<span class="rating"><%= star_rating(course.average_rating) %></span>
<small>Added <%= time_ago(course.created_at) %></small>
```

### Flash Message Helper

Flash messages are those notifications that survive a single redirect - "Course saved successfully", "Invalid email or password", that sort of thing. Sinatra doesn't include them by default, but they're straightforward to build yourself and I've found rolling your own gives you more control than reaching for a gem.

```ruby
# helpers/flash_helper.rb
module FlashHelper
  def flash
    session[:flash] ||= {}
  end

  def flash_now
    @flash_now ||= {}
  end

  def set_flash(type, message)
    flash[type.to_s] = message
  end

  def flash_messages
    messages = flash.merge(flash_now)
    session.delete(:flash)
    messages
  end
end
```

Setting a flash message before a redirect looks like this:

```ruby
post '/courses/:slug/enroll' do
  require_login!
  @course = Course.find_by_slug!(params[:slug])

  if current_user.enroll_in!(@course)
    flash[:success] = "You're enrolled in #{@course.title}!"
    redirect "/learn/#{@course.slug}"
  else
    flash[:error] = 'Enrollment failed. Please try again.'
    redirect "/courses/#{@course.slug}"
  end
end
```

And in the layout template, displaying them is just a loop:

```erb
<% flash_messages.each do |type, message| %>
  <div class="alert alert-<%= type %>">
    <%= message %>
  </div>
<% end %>
```

For immediate feedback without a redirect, `flash_now` is what you want - it only shows on the current request and never touches the session:

```ruby
post '/login' do
  user = User.authenticate(params[:email], params[:password])

  if user
    login!(user)
    redirect session.delete(:return_to) || '/dashboard'
  else
    flash_now[:error] = 'Invalid email or password.'
    erb :'sessions/new'
  end
end
```

## Creating Custom Extensions

A Sinatra extension is a Ruby module that hooks into Sinatra's class methods when you call `register`. I think of extensions as the next step up from helpers - where a helper adds methods, an extension can add settings, helpers, routes & hooks all together in one self-contained package (think "plug and play").

The structure is clean: your module defines a `registered` method that Sinatra calls with the application class as an argument. You use that to set up whatever you need.

Here's a request timing extension - I've found something like this invaluable for catching slow endpoints before users do:

```ruby
# lib/extensions/request_timer.rb
module Sinatra
  module RequestTimer
    def self.registered(app)
      app.set :timing_header, 'X-Response-Time'
      app.set :timing_log_slow_threshold, 500   # milliseconds

      app.helpers Helpers

      app.before do
        env['request_timer.start'] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      app.after do
        start = env['request_timer.start']
        return unless start

        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(2)

        response.headers[settings.timing_header] = "#{elapsed_ms}ms"

        if elapsed_ms > settings.timing_log_slow_threshold
          logger.warn "SLOW REQUEST: #{request.request_method} #{request.path} took #{elapsed_ms}ms"
        end
      end
    end

    module Helpers
      def request_start_time
        env['request_timer.start']
      end

      def elapsed_ms
        return 0 unless request_start_time
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - request_start_time) * 1000).round(2)
      end
    end
  end

  register RequestTimer
end
```

Register it in your app class and you're done:

```ruby
require_relative 'lib/extensions/request_timer'

class App < Sinatra::Base
  register Sinatra::RequestTimer

  # Optionally override defaults
  set :timing_log_slow_threshold, 200
end
```

Every request now gets an `X-Response-Time` header and anything taking more than 200ms gets logged as slow. Zero changes to individual routes required - that's the beauty of the extension pattern.

Here's another one I've used in production - a maintenance mode extension:

```ruby
# lib/extensions/maintenance_mode.rb
module Sinatra
  module MaintenanceMode
    def self.registered(app)
      app.set :maintenance_mode, false
      app.set :maintenance_allowed_ips, ['127.0.0.1']

      app.helpers Helpers

      app.before do
        next unless settings.maintenance_mode
        next if settings.maintenance_allowed_ips.include?(request.ip)

        halt 503, erb(:'errors/maintenance', layout: :'layouts/application')
      end
    end

    module Helpers
      def maintenance_mode?
        settings.maintenance_mode
      end
    end
  end

  register MaintenanceMode
end
```

```ruby
class App < Sinatra::Base
  register Sinatra::MaintenanceMode

  configure :production do
    # Flip this to true when deploying
    set :maintenance_mode, ENV.fetch('MAINTENANCE_MODE', 'false') == 'true'
    set :maintenance_allowed_ips, ['203.0.113.10']  # Your office IP
  end
end
```

Flip maintenance mode on without a code deploy:

```bash
MAINTENANCE_MODE=true bundle exec rackup
```

What I like about the extension pattern is that each concern is entirely self-contained. The before/after hooks, settings & helpers for a feature all travel together in one module rather than being scattered across your app class. When you want to remove it, you remove one file and one `register` call.

## Workshop: Putting Our Initial Structure Together

Let's assemble the skeleton of LearnHub using everything from this chapter. We're not implementing full business logic yet - we're building the frame that the rest of the book will fill in. Once this is in place, adding features feels very satisfying because there's already a clear home for everything.

Start by creating the directory structure:

```bash
mkdir -p learnhub/{config/initializers,controllers,models,helpers,lib/extensions,views/{layouts,courses,instructor,sessions,errors,partials},public/{css,js,images},db/migrations,spec/{models,controllers}}

touch learnhub/{.env,.env.example,Gemfile,Rakefile,app.rb,config.ru}
touch learnhub/config/{application.rb,database.yml}
touch learnhub/config/initializers/{database.rb,redis.rb}
touch learnhub/controllers/{base_controller.rb,courses.rb,enrollment.rb,instructor.rb,sessions.rb}
touch learnhub/helpers/{auth_helper.rb,view_helper.rb,flash_helper.rb}
touch learnhub/models/{user.rb,course.rb,lesson.rb,enrollment.rb,review.rb}
```

Here's the `Gemfile` for everything we've covered so far:

```ruby
# Gemfile
source 'https://rubygems.org'

ruby '3.3.0'

gem 'sinatra', '~> 4.0'
gem 'sinatra-contrib', '~> 4.0'   # namespace, respond_with, etc.
gem 'puma', '~> 6.0'               # web server
gem 'activerecord', '~> 7.1'       # models
gem 'pg', '~> 1.5'                 # PostgreSQL
gem 'redis', '~> 5.0'              # caching and sessions
gem 'dotenv', '~> 3.0'             # .env loading
gem 'rake', '~> 13.0'              # tasks

group :development do
  gem 'rerun'                       # auto-reload on file changes
  gem 'pry'
  gem 'rubocop', require: false
end

group :test do
  gem 'rspec'
  gem 'rack-test'
  gem 'factory_bot'
  gem 'faker'
end
```

The `config/application.rb` configuration module - notice how `ENV.fetch` with a block means missing secrets blow up loudly rather than silently:

```ruby
# config/application.rb
module LearnHub
  module Config
    extend self

    def app_name
      'LearnHub'
    end

    def env
      ENV.fetch('RACK_ENV', 'development')
    end

    def production? = env == 'production'
    def development? = env == 'development'
    def test? = env == 'test'

    def database_url
      ENV.fetch('DATABASE_URL', "postgres://localhost/learnhub_#{env}")
    end

    def redis_url
      ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')
    end

    def session_secret
      ENV.fetch('SESSION_SECRET') do
        raise KeyError, 'SESSION_SECRET must be set in .env'
      end
    end
  end
end
```

The database initializer - kept simple on purpose, each initializer should do one thing:

```ruby
# config/initializers/database.rb
require 'active_record'
require 'logger'

ActiveRecord::Base.establish_connection(LearnHub::Config.database_url)

if LearnHub::Config.development?
  ActiveRecord::Base.logger = Logger.new($stdout)
  ActiveRecord::Base.logger.level = Logger::DEBUG
end
```

The base controller, which every other controller will inherit from:

```ruby
# controllers/base_controller.rb
require 'sinatra/base'

class BaseController < Sinatra::Base
  configure do
    set :views, File.join(File.dirname(__FILE__), '..', 'views')
    enable :logging
  end

  helpers AuthHelper
  helpers ViewHelper
  helpers FlashHelper

  not_found do
    erb :'errors/404'
  end

  error do
    @error = env['sinatra.error']
    logger.error "#{@error.class}: #{@error.message}\n#{@error.backtrace.first(5).join("\n")}"
    erb :'errors/500'
  end
end
```

The sessions controller handles login & logout:

```ruby
# controllers/sessions.rb
class SessionsController < BaseController
  get '/login' do
    redirect '/dashboard' if logged_in?
    erb :'sessions/new'
  end

  post '/login' do
    user = User.authenticate(params[:email], params[:password])

    if user
      login!(user)
      redirect session.delete(:return_to) || '/dashboard'
    else
      flash_now[:error] = 'Invalid email or password.'
      erb :'sessions/new'
    end
  end

  delete '/logout' do
    logout!
    flash[:info] = 'You have been logged out.'
    redirect '/login'
  end
end
```

The courses controller handles the public-facing course catalog - already has basic filtering & search hooks stubbed in:

```ruby
# controllers/courses.rb
class CoursesController < BaseController
  get '/courses' do
    @courses = Course.published.order(created_at: :desc)
    @courses = @courses.where(category: params[:category]) if params[:category]
    @courses = @courses.search(params[:q]) if params[:q]
    erb :'courses/index'
  end

  get '/courses/:slug' do
    @course = Course.find_by_slug!(params[:slug])
    @enrolled = enrolled_in?(@course)
    @reviews  = @course.reviews.recent.limit(10)
    erb :'courses/show'
  end
end
```

And the main `app.rb` wires it all together:

```ruby
# app.rb
require 'sinatra/base'

require_relative 'config/application'
require_relative 'helpers/auth_helper'
require_relative 'helpers/view_helper'
require_relative 'helpers/flash_helper'
require_relative 'controllers/base_controller'
require_relative 'controllers/sessions'
require_relative 'controllers/courses'
require_relative 'controllers/enrollment'
require_relative 'controllers/instructor'

class App < Sinatra::Base
  configure do
    set :app_name, LearnHub::Config.app_name
    set :root, File.dirname(__FILE__)
    set :views, File.join(root, 'views')
    set :public_folder, File.join(root, 'public')
    set :sessions, true
    set :session_secret, LearnHub::Config.session_secret
    set :method_override, true
  end

  configure :development do
    set :logging, true  # configure logger level separately via Logger.new if needed
    set :dump_errors, true
    set :show_exceptions, true
  end

  configure :production do
    set :logging, false
    set :dump_errors, false
    set :show_exceptions, false
  end

  use SessionsController
  use CoursesController
  use EnrollmentController
  use InstructorController

  get '/' do
    @featured_courses = Course.published.featured.limit(6)
    erb :home
  end
end
```

And finally the `config.ru` that Rack reads at startup:

```ruby
# config.ru
require 'dotenv/load'

require 'bundler/setup'
Bundler.require(:default, ENV.fetch('RACK_ENV', 'development').to_sym)

Dir[File.join(__dir__, 'config', 'initializers', '*.rb')].sort.each { |f| require f }
Dir[File.join(__dir__, 'models', '**', '*.rb')].sort.each { |f| require f }

require_relative 'app'

run App
```

Start it up:

```bash
cd learnhub
bundle install
bundle exec rackup
```

You should see Puma start and bind to `http://127.0.0.1:9292`. Nothing will render yet because we haven't created the views or models, but the boot sequence will run cleanly and that's all we need to confirm the structure is solid.

You can verify the config module is wired correctly with a quick one-liner:

```bash
bundle exec ruby -e "require_relative 'config/application'; puts LearnHub::Config.app_name"
# => LearnHub
```

This skeleton is the foundation everything else in this book builds on. In the next chapter we'll fill in the model layer with ActiveRecord and get real data flowing through these routes.

One last thing worth saying - the structure I've laid out here is a suggestion, not a law (doesn't every project?). Some teams prefer `routes/` over `controllers/`. Some keep helpers directly in `app.rb` until the file gets too big to bear. The right structure is whatever your team agrees on and actually sticks to. Consistency within a project matters far more than which particular layout you pick.

As long as a new developer - or you, six months from now - can open the project and immediately understand where things live, you've done your job.
