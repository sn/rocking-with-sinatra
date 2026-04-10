# Chapter 1 - Important Concepts

It's important to remember that Sinatra is an amazingly flexible micro framework with a top level DSL and is not a feature packed framework like Ruby on Rails. It’s purposefully built to have just enough functionality to give you what you need to get going without being in your way or polluting your workspace. There are incredibly useful helpers and extensions available that can be found with a bit of Googling, not to mention the thousands of Ruby Gems available to use.

Sinatra literally gives you a blank slate and all the application design decisions are entirely up to you. I found it much easier to work with Sinatra once I completely let go on any preconceptions I had about how web application *must* be built.

The simplicity of Sinatra is why it's so powerful - it fits into your brain and it’s up to you to implement the methodologies, approaches and application structures that best suite your project. Generally, you would use components that you already know instead of learning a whole new framework.

It all comes down to good project organization and sufficient upfront planning (doesn't every project?), I would recommend reading up a bit more on MVC, HMVC or other software architectural patterns to get a good understanding of how it can solve common problems you might encounter during development.

Sinatra’s lack of opinions is one of it’s greatest benefits. It won’t stop you from writing unmaintainable code however - that’s our/your responsibility.

There is no ‘one size fits all’ approach to building Sinatra applications - you have the freedom to experiment and work the way you need to with the added benefit of getting started in mere seconds.

We’ll be working through organizing your Sinatra project using MVC in a later chapter.

First, let’s start with talking about the difference between classic and modular style applications in Sinatra as this tends to be a point of confusion for many developers exploring Sinatra.

### Classic & Modular Style Applications

Sinatra can be used in two different ways, both have slightly different use cases and requirements:

Let’s take a look:

**Classic Style** is generally used more when creating smaller micro-sites or apps. I use the word ‘generally’ loosely here. These apps usually run from a single application file or two:

_app.rb:_

```ruby
require 'sinatra'

get '/' do
  erb :"homepage"
end

get '/products' do
  @products = [
	{:name => "Mac Pro", :price => 1200, :sku => "mbp0001"},
	{:name => "HP P1102w", :price => 389, :sku => "hp0001"}
  ]
  erb :"products"
end

post '/product/purchase/:sku' do
  # Start checkout/purchase routine
end
```

In your _Terminal:_

```bash
ruby app.rb
```

Some developers don’t like the classic style applications because it pollutes the global namespace in Ruby, but it’s subjective and if the classic approach is the perfect tool for problem you are attempting to solve, then do so.

One thing you should take note of is that running Sinatra in classic style prevents you from running more than one Sinatra application per Ruby process.

When you use `require 'sinatra'`, it automatically sets up the application with a few default settings for you - think ‘plug and play’.

**Modular Style** is simply a way to write your app as independent modules that can run within the same parent application. This is great if you plan to use more advanced structuring of your application files - we'll talk more about this in a later.

**Important**: If you are planning to package your app as a gem or extension, you will need to use the modular approach.

Unlike in classic mode, some options will not be automatically configured for you when you create your apps using the modular approach.

This approach uses `require ‘sinatra/base’` instead of `require ‘sinatra’`.

Here’s an example:

_app.rb:_

```ruby
require 'sinatra/base'

class MyStore < Sinatra::Base
     configure do
       set :logging, true
       set :sessions, true
       set :dump_errors, false
     end

	get '/' do
		view_variables = {
		  :title => "My Awesome Store"
		}
		erb :"homepage", layout: false, locals: view_variables
	end
end
```

_api.rb:_

```ruby
require ‘sinatra/base’
require ‘sinatra/contrib’
require ‘net/http’
require ‘json’

class MyAPI < Sinatra::Base
     configure do
	  set :logging, true
	  set :sessions, false
	  set :dump_errors, false
     end

	helpers Sinatra::JSON

	get '/weather.json' do
	  @uri = URI('http://api.openweathermap.org/data/2.5/weather?q=London,uk&APPID=<YOUR API KEY HERE>')
	  @resp = JSON.parse(Net::HTTP.get(@uri))

	  json({
		:name => @resp["name"],
		:weather => @resp["weather"]
	  })
	end
end    
```

_config.ru:_

```ruby
require './app'
require './api'

map "/" do
  run MyStore
end

map "/api" do
  run MyAPI
end
```

In your _Terminal:_

```bash
bundle exec rackup
```

In the modular style example above, we have two of our own classes extending the `Sinatra::Base` class, each inheriting all functionality from the `Base` class and handling requests in their own context and scope. The MyStore application will be available to any requests on the **root url** ‘/‘ and the MyAPI app will respond to requests on the **api url** `/api` - this is specified in the Rack configuration file (config.ru).

You'll also notice that we're requiring `sinatra/contrib` in `api.rb ` - it's a project that closely follows Sinatra's release cycle and contains a collection of commonly used extensions, you will undoubtedly find some of them useful.

We've used the built-in `Sinatra.helpers()` method to register the `Sinatra::JSON helper` inside our `MyAPI` class. This makes the `json({:key => val})` method available to us. The `json()` method automatically sets the output content-type to `application/JSON` for us before sending the response back to the browser.

You will usually find larger applications built using the modular approach because you can completely decouple components of your app - something that’s very useful in multi-faceted systems with dashboards, websites, CMS's, API’s etc.

Install `Sinatra::Contrib using`:

`gem install sinatra-contrib`

More information:

* [Sinatra::Contrib Documentation](https://sinatrarb.com/contrib/)
* [Sinatra Configuration Settings](https://sinatrarb.com/configuration.html)

### A Brief Introduction to Rack

Rack provides a minimal, bare metal interface between web servers supporting Ruby and Ruby frameworks. It's a layer that sits between the web server and your Ruby application code, translating incoming HTTP requests into a standard format your app can work with.

Rack is the de facto standard for building Ruby web applications due to the fact that it provides a simple, unified interface for framework creators to work with. In fact, you don't need to use a framework at all to create a Ruby web application, you can simply use Rack and what ever libraries you usually use.

If you've written some code that meets the requirements of the Rack specification, you can load it up in any Rack-compatible Ruby server like Puma or Falcon.

A bare Rack application is simply any Ruby object that responds to `call`, accepts an environment hash and returns an array of `[status, headers, body]` - that's it, nothing more:

```ruby
# config.ru
app = proc do |env|
  [200, { 'content-type' => 'text/plain' }, ['Hello from Rack!']]
end

run app
```

Sinatra builds on top of this simple interface, giving you routing, templates & helpers while remaining a Rack application at its core. Understanding this is useful because it means you can drop down to Rack level whenever Sinatra doesn't have a built-in solution for something.

##### The Rack Environment Hash

Every request that hits your Sinatra app arrives as a Rack environment hash (`env`). This hash contains everything about the incoming request and I find it helpful to know what's available:

```ruby
get '/debug' do
  # Some useful env keys:
  # env['REQUEST_METHOD']   => "GET"
  # env['PATH_INFO']        => "/debug"
  # env['QUERY_STRING']     => "foo=bar"
  # env['HTTP_HOST']        => "localhost:9292"
  # env['rack.input']       => the request body (IO object)
  # env['rack.session']     => session hash (if sessions enabled)

  content_type :json
  env.select { |k, _| k.start_with?('HTTP_', 'REQUEST_', 'PATH_', 'QUERY_') }.to_json
end
```

Understanding the `env` hash is important because Rack middleware operates by reading & modifying it before your app sees the request. For example, `Rack::Session::Cookie` reads/writes `env['rack.session']`, and `Rack::Protection` checks headers like `env['HTTP_ORIGIN']`.

##### Using Rack Middleware

Adding middleware to your Sinatra app is straightforward and works just as you would with any Rack application. Here's an example in a modular app:

```ruby
class App < Sinatra::Base
  use Rack::CommonLogger
  enable :sessions
  set :session_secret, ENV.fetch('SESSION_SECRET')
end
```

Note that Sinatra already includes `Rack::Protection` when sessions are enabled, so you don't need to add it yourself in a Sinatra app.

Or in `config.ru` for more control:

```ruby
require './app'

use Rack::CommonLogger
use Rack::Deflater  # Gzip compression
run App
```

Rack middleware is one of the most powerful features available to you as a Ruby web developer. Anything that can be expressed as "do this for every request" is a good candidate for middleware - logging, authentication checks, rate limiting, CORS headers and more. I would recommend exploring the [Rack documentation](https://github.com/rack/rack) when you have some time, there's a lot of useful functionality built in.

### Software Architecture Patterns

As I mentioned at the beginning of this chapter, Sinatra doesn't impose any particular architecture on your application - it's entirely up to you. A 50-line API can live happily in a single `app.rb`, but a course marketplace with user authentication, payments & video processing definitely cannot.

I would recommend reading up on MVC (Model-View-Controller) as it's the most common pattern for web applications and the one we'll use throughout this book:

- **Models** - Your data layer. ActiveRecord classes that map to database tables, handle validations & encapsulate business logic.
- **Views** - ERB (or Haml/Slim) templates that render HTML. They should contain presentation logic only.
- **Controllers** - In Sinatra, these are your route handlers. They receive requests, interact with models and render views.

We'll be working through organizing your Sinatra app into a clean MVC structure in Chapter 6, so don't worry too much about it now - just keep the concept in the back of your mind as you work through the next few chapters.
