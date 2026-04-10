# Chapter 2 - Working with Routes & Conditions

Efficient routing is fundamental to how well a web application functions, it’s the ability to map incoming requests to methods inside your code using patterns that match request URL’s.

Luckily for us, Sinatra has a powerful routing mechanism built into it that gives you the flexibility you need for modern day apps & API’s.

Here’s a simple example in a _classic style_ app:

```ruby
require ‘sinatra’

 get ‘/products’ do
   # Display the products page
 end

 post ‘/products’ do
   # Create a new product
 end

 put ‘/products/:id’ do
   @product = Product.find_by_id(params[:id])

   if @product
     @product.name = params[:product_name]
     @product.save
   else
     halt 404, “Product not found”
   end
 end

 delete ‘/products/:id’ do
   @product = Product.find_by_id(params[:id])

   if @product
     @product.destroy
   else
     halt 404, “Product not found”
   end
 end
```

Here’s the same example as above in _modular style_:

```ruby
 require ‘sinatra/base’

 class MyApp < Sinatra::Base
  get ‘/products’ do
    # Display the products page
  end

  post ‘/products’ do
    # Create a new product
  end

  put ‘/products/:id’ do
    @product = Product.find_by_id(params[:id])

    if @product
      @product.name = params[:product_name]
      @product.save
    else
      halt 404, “Product not found”
    end
  end

  delete ‘/products/:id’ do
    @product = Product.find_by_id(params[:id])

    if @product
      @product.destroy
    else
      halt 404, “Product not found”
    end
  end
 end
```

As you’ll notice, there’s no difference in route handling between the module and classic approaches.

Sinatra routes are simply Ruby methods with an associated code block that are executed every time a request matches the given route pattern.

The `:id` part of the route pattern is a *named parameter* and will be accessible in your code from the *params* hash: `params[:id]`, but I’ll describe these in further detail later in this chapter.

**Important:** Routes are matched in the exact order that they are defined in your code, this means that second route in the below example will never get matched because we have the exact same pattern further up in the code.

```ruby
require ‘sinatra’

get ‘/products/:id’ do
  # Display the products page
end

get ‘/products/12’ do
  # Route that won’t get fired
end
```

For the above code to work as you expect it to, you’ll need to switch the two routes around so that the route containing the named parameter can be used as a kind of ‘catch-all’ route at the end. The explicit routes should always be added towards the top of your route file or controller. I can guarantee you that this has been the source a many hours of frustration by developers working with Sinatra.

Route method names correspond to [HTTP 1.1](http://www.w3.org/Protocols/HTTP/1.1/draft-ietf-http-v11-spec-01.html) request method names to make things easier to remember.

Available Routing Methods in Sinatra:

| Method | General use-case example |
| ---- | ----- |
| get() | Performing basic HTTP GET requests like loading pages|
| post() | Used when posting form data |
| put() | Used when updating resources |
| patch() | Similar to post(), but used when updating one field of a resource |
| delete() | Used when deleting resources |
| options() | Determine options available for an associated resource |
| link() | Link relationships between existing resources |
| unlink() | Unlink relationships between existing resources |

When building user facing web application, you’ll be using get() and post() methods the majority of the time.

The additional request methods become useful when you start creating REST API’s as I’ll demonstrate later in the book.

#### Named Parameters

Suppose you have built a CRM that uses segments to manage the customers you have, what would be the best way to retrieve a list of customers for any given segment?

It’s actually quite simple:

```ruby
get ‘/customers/:segment_name’ do
  @segment = Segment.where(:name => params[:segment_name]).first

  if @segment
	@customers = Customer.where(“segment_id = ?”, @segment.id)
	erb :”customers/by_segment”
  else
	halt 404, “The customer segment could not be found”
  end
end
```

In your `customers/by_segment.erb` view, you could have something like this:

```erb
<h2>Customers in <%= @segment.name %> segment</h2>
<% @customers.each do |c| %>
  <h5><%= c.name %></h5>
  <p><%= c.email %></p>
<% end %>
```

You can specify as many named parameters as needed in your route pattern, their corresponding values will be accessible from the `params` hash.

#### Wildcard Routing

Wildcard routing is useful when you are matching routes that might have many different contextual values, here’s an example:

```ruby
# Matches: http://mysite.com/products/1/macbook-pro
# Matches: http://mysite.com/products/2/mac-mini
# Matches: http://mysite.com/products/3/dell-laptop
get ‘/products/:id/*’ do
  @product = Product.find_by_id(params[:id])

  if @product
	erb :”product/show”
  else
	halt 404, “Product not found”
  end
end
```

Even though we never actually need the values matched in the wildcard pattern in the above example, it makes sure we have good looking & SEO friendly URL’s to work with.

If we need to use the values matched by the wildcard pattern, we can access them in the following two ways:

**Using the params[:splat] Array**

A simple example allowing a user to download a file hosted on your server:

**Important:** Always sanitize file paths from user input to prevent directory traversal attacks.

```ruby
# Matches: http://mysite.com/download/portfolio.pdf
# Matches: http://mysite.com/download/sample.psd
# Matches: http://mysite.com/download/project.zip
get ‘/download/*.*’ do
  filename = “#{params[:splat].first}.#{params[:splat].last}”
  halt 400 if filename.include?(‘..’) || filename.start_with?(‘/’)
  path = File.join(settings.public_folder, ‘downloads’, filename)

  if File.exist?(path)
    send_file(path, disposition: ‘attachment’, filename: filename)
  else
    halt 404, “File not found”
  end
end
```

**Using Block Parameters**

```ruby
# Matches: http://mysite.com/download/portfolio.pdf
# Matches: http://mysite.com/download/sample.psd
# Matches: http://mysite.com/download/project.zip
get ‘/download/*.*’ do |name, ext|
  file = “#{name}.#{ext}”
  path = File.join(settings.public_folder, ‘downloads’, file)

  if File.exist?(path)
    send_file(path, disposition: ‘attachment’, filename: file)
  else
    halt 404, “File not found”
  end
end
```

The params[:splat] array is a regular Ruby Array and it’s elements can be accessed as you would with any other array.

If no matches are found, the `:splat` element won’t exist in the `params` hash - so do check it.

```ruby
get ‘/files/*’ do
  parts = params[:splat]  # Returns an Array
  if parts.empty?
    halt 400, "No file specified"
  end
  # parts[0] contains the matched path
  "Requested: #{parts.first}"
end
```

#### Routing with Regular Expressions

For a bit more power, you can use regular expressions to match routes using the **params** hash & **block method** as you do wildcard routing, here’s how:

```ruby
# Matches: http://mysite.com/download/project.zip
# Matches: http://mysite.com/download/portfolio.pdf
get %r{/download/([\w]+).(zip|pdf)} do
  file = “#{params[:captures].first}.#{params[:captures].last}”
  path = File.join(settings.public_folder, ‘downloads’, file)

  if File.exist?(path)
    send_file(path, disposition: ‘attachment’, filename: file)
  else
    halt 404, “File not found”
  end
end
```

The values for the matches that occur within the Regex Group brackets `([\w]+)` and `(zip|pdf)`, will be available in the `params[:captures]` array. Note that in the above example, only filenames with either a .zip or .pdf extension will match.

Regular expressions can be difficult to understand at times, but are rather fun when you get the hang of it.

I would recommend having a good [regular expression](http://www.cheatography.com/davechild/cheat-sheets/regular-expressions/) cheat sheet and [testing tool](http://krillapps.com/patterns/) at hand if you plan to use this kind of routing regularly. Personally, I rarely use Regex routing in Sinatra.

#### Adding URL Query String Parameters

In addition to the above methods of matching routes, you can easily add query string parameters to your URL's that will also be accessible from the `params` hash:

`http://mysite.com/dashboard?view=days&group=users`

Translates to:

```ruby
get ‘/dashboard’ do
  @view = params[:view] #days
  @group = params[:group] #users
end
```

The same goes for `POST` variables from web forms:

```ruby
<form method=“POST” action=“/dashboard”>
  <input type=“text” name=“view” value=“days” />
  <input type=“text” name=“group” value=“users” />
  <input type=“submit” value=“Submit” />
</form>
```

Translates to:

```ruby
post ‘/dashboard’ do
  @view = params[:view] #days
  @group = params[:group] #users
end
```

It’s important to note that the `params` hash is what you’ll use to read most user input in your code - similar to the way it works in Ruby on Rails.

#### Routing Conditions

A routing condition ensures that a route is only matched if the provided condition is also met, apart from the actual route match. Sinatra has a few built-in conditions you can use, but it’s common practice to create your own. They are currently poorly documented, but they can save you a lot of code if you know how to use them correctly.

Let’s start by first defining a condition that checks to see if a user is successfully logged in (common use-case) before they are able to access a page:

_app.rb_

```ruby
# Helper
def logged_in?
   !session[:user_id].nil?
end

# Define the condition
set(:auth) do
  condition do
	if !logged_in?
	  redirect ‘/signin’
	else
	  @user = User.find_by_id(session[:user_id])
	end
  end
end

get ‘/dashboard’, :auth => true do
  if @user
	erb :”dashboard/index”
  else
	halt 401, “Unauthorized”
  end      
end
```

In the above example, we first create a helper method `logged_in?` to check if a `user_id` has been saved into the current session. If yes, this would mean that we have a user successfully signed in.

Next up, we define our custom condition `set(:auth)` that uses our helper method to determine if a use is logged in. If not, we immediately redirect the request back to the log in page. If the user is logged in, we load the user data into an instance variable that becomes accessible to all routing methods of your application.

When defining the route method, you now add a second parameter to it to indicate that a condition is expected `:auth => true` - a hash with a key matching the name of our custom defined condition.

If false is returned from the condition block, the accompanying route will not be matched and Sinatra will attempt to match the next route in the queue if any are available.

I mentioned earlier that routes will get matched in the order that they are defined and therefore only the first of two identical routes will be executed. This behavior is not entirely true when using conditions, here’s why:

```ruby
set(:demo) do
  condition do
	false
  end
end

get ‘/user/settings’, :demo => true do
  # This route will never match
end

get ‘/user/settings’ do
  # This route will be matched
end
```

The custom condition `:demo` will always return `false` in our example, meaning that the first routes' method condition will never be matched even with a positive URL match. Sinatra will skip over it and execute the second route method instead.

You can also pass parameters directly into the conditions and use them in your evaluation block of the condition, let’s re-write the above example accordingly using a the :demo condition from above:

```ruby
set(:demo) do |val|
  condition do
	val
  end
end
```

```ruby
get ‘/user/settings’, :demo => false do
  # This route won’t be matched
end
```

```ruby
get ‘/user/settings’, :demo => true do
  # This route will be matched
end
```

Here we added a parameter to the condition block `set(:demo) do |val|` and that same value is being returned directly from the condition. This means that we can directly control whether or not the condition will pass by simply changing the boolean value of `:demo` when calling the corresponding route method.

Conditions can also accept multiple parameters by using the splat operator, let’s take a look in another simple example:

```ruby
set(:demo) do |*params|
  condition do
      # Utilise the params splat values
	 if params.first == params.last
	    true # condition passes
	 else
	    false # condition fails
	 end
  end
end

get ‘/user/settings’, :demo => [:param1, :param2, …etc] do
  erb :”user/settings”
end
```

The important thing to note here is the `*params` Ruby splat operator. It is an array of all parameters passed into the condition. You can pass as many parameters into the condition as you need and access them using regular Ruby [array accessor] methods.

In the above example, the condition will pass if the first value in the params array matches the last and fails if it does not.

Sinatra also has built in conditions that you can use, have a look at [the documentation] for examples of these.

## Production Routing Patterns

Let me share some patterns I've found invaluable when building real applications with Sinatra.

### API Versioning

One pattern that's saved me countless headaches is API versioning through routes. You'll need the `sinatra-contrib` gem for the `namespace` helper - add `require 'sinatra/namespace'` to your app:

```ruby
# Using namespaces for clean API versioning (requires sinatra/namespace)
namespace '/api/v1' do
  get '/courses' do
    content_type :json
    Course.all.map(&:to_v1_api).to_json
  end
end

namespace '/api/v2' do
  get '/courses' do
    content_type :json
    # V2 includes more fields
    Course.all.map(&:to_v2_api).to_json
  end
end
```

### Route Organization for Large Apps

When your app grows beyond a dozen routes, organization becomes critical. The cleanest approach is to define separate Sinatra apps and mount them in `config.ru`:

```ruby
# routes/admin.rb
class AdminRoutes < Sinatra::Base
  before do
    halt 403 unless current_user&.admin?
  end
  
  get '/users' do
    @users = User.all
    erb :'admin/users'
  end
  
  delete '/users/:id' do
    User.find(params[:id]).destroy
    redirect '/admin/users'
  end
end

# routes/api.rb
class APIRoutes < Sinatra::Base
  before do
    content_type :json
  end
  
  get '/status' do
    {status: 'ok', time: Time.now}.to_json
  end
end

# config.ru
require './routes/admin'
require './routes/api'
require './app'

map('/admin') { run AdminRoutes }
map('/api')   { run APIRoutes }
map('/')      { run App }
```

### Content Negotiation

Here's a pattern for handling different content types elegantly:

```ruby
get '/report/:id' do
  @report = Report.find(params[:id])
  
  respond_to do |format|
    format.html { erb :report }
    format.json { @report.to_json }
    format.pdf  { @report.to_pdf }
  end
end

# Helper to make this work
helpers do
  def respond_to
    format = Format.new(request.accept)
    yield format
    format.finish
  end
end

class Format
  def initialize(accept_header)
    @accept = accept_header
    @response = nil
  end
  
  def html(&block)
    @response = block if @accept.include?('text/html')
  end
  
  def json(&block)
    @response = block if @accept.include?('application/json')
  end
  
  def pdf(&block)
    @response = block if @accept.include?('application/pdf')
  end
  
  def finish
    @response ? @response.call : halt(406, "Not Acceptable")
  end
end
```

### Subdomain Routing

For multi-tenant applications, subdomain routing is essential:

```ruby
# Route based on subdomain
before do
  @subdomain = request.host.split('.').first
  @tenant = Tenant.find_by_subdomain(@subdomain)
  halt 404, "Tenant not found" unless @tenant
end

get '/' do
  # Each tenant gets their own homepage
  erb :tenant_home, locals: {tenant: @tenant}
end
```

### Advanced Condition Examples

Let's look at some more practical condition examples:

```ruby
# Rate limiting condition
set(:rate_limit) do |num|
  condition do
    ip = request.ip
    key = "rate_limit:#{ip}"
    
    count = $redis.incr(key)
    $redis.expire(key, 3600) if count == 1
    
    if count > num
      halt 429, "Rate limit exceeded"
    end
  end
end

get '/api/search', rate_limit: 100 do
  # Limited to 100 requests per hour per IP
  perform_search(params[:q])
end

# Feature flag condition
set(:feature) do |flag|
  condition do
    unless FeatureFlag.enabled?(flag)
      halt 404
    end
  end
end

get '/beta/ai-assistant', feature: :ai_assistant do
  erb :ai_assistant
end

# Complex role-based condition
set(:role) do |*allowed_roles|
  condition do
    unless current_user && allowed_roles.any? { |r| current_user.has_role?(r) }
      halt 403, "Access denied"
    end
  end
end

get '/admin/dashboard', role: [:admin, :super_admin] do
  erb :'admin/dashboard'
end
```

### Performance Tips

Route matching has performance implications. Here are some tips:

1. **Order matters**: Put specific routes before generic ones
2. **Avoid regex when possible**: String matching is faster
3. **Use conditions wisely**: They add overhead
4. **Cache route results**: For expensive operations

```ruby
# Good - specific routes first
get '/api/v2/courses/:id' do
  # Specific handler
end

get '/api/v2/*' do
  # Generic handler
end

# Cache expensive route results
get '/reports/monthly' do
  cache_key = "monthly_report:#{Date.today.month}"
  
  @report = settings.redis.get(cache_key)
  unless @report
    @report = generate_expensive_report
    settings.redis.setex(cache_key, 3600, @report)
  end
  
  erb :monthly_report
end
```

## Real-World Example: Multi-Tenant Course Platform

Let's put it all together with a production example from our Udemy clone:

```ruby
class CourseApp < Sinatra::Base
  # Helpers
  helpers do
    def current_tenant
      @current_tenant ||= Tenant.find_by_domain(request.host)
    end
    
    def authenticate!
      halt 401 unless session[:user_id]
    end
    
    def current_user
      @current_user ||= User.find(session[:user_id]) if session[:user_id]
    end
  end
  
  # Conditions
  set(:instructor_only) do
    condition do
      authenticate!
      halt 403 unless current_user.instructor?
    end
  end
  
  set(:enrolled) do
    condition do
      authenticate!
      course = Course.find_by_slug(params[:slug])
      halt 403 unless current_user.enrolled_in?(course)
    end
  end
  
  # Public routes
  get '/courses' do
    @courses = current_tenant.courses.published
    
    # Filtering
    @courses = @courses.where(category: params[:category]) if params[:category]
    @courses = @courses.search(params[:q]) if params[:q]
    
    # Sorting
    sort = params[:sort] || 'popular'
    @courses = case sort
    when 'popular' then @courses.order(enrollments_count: :desc)
    when 'newest' then @courses.order(created_at: :desc)
    when 'price_low' then @courses.order(price: :asc)
    when 'price_high' then @courses.order(price: :desc)
    else @courses
    end
    
    @courses = @courses.page(params[:page])
    erb :courses
  end
  
  get '/courses/:slug' do
    @course = Course.find_by_slug!(params[:slug])
    @enrolled = current_user&.enrolled_in?(@course)
    @reviews = @course.reviews.recent.limit(10)
    
    erb :course_detail
  end
  
  # Student routes
  post '/courses/:slug/enroll' do
    authenticate!
    @course = Course.find_by_slug!(params[:slug])
    
    enrollment = current_user.enroll_in!(@course)
    
    # Process payment if needed
    if @course.paid?
      result = PaymentProcessor.charge(
        user: current_user,
        amount: @course.price,
        description: "Enrollment in #{@course.title}"
      )
      
      unless result.success?
        enrollment.destroy
        halt 402, "Payment required"
      end
    end
    
    redirect "/learn/#{@course.slug}"
  end
  
  get '/learn/:slug', enrolled: true do
    @course = Course.find_by_slug!(params[:slug])
    @progress = current_user.progress_for(@course)
    @current_lesson = @progress.current_lesson
    
    erb :course_player
  end
  
  get '/learn/:slug/lessons/:lesson_id', enrolled: true do
    @course = Course.find_by_slug!(params[:slug])
    @lesson = @course.lessons.find(params[:lesson_id])
    
    # Track progress
    current_user.mark_lesson_complete(@lesson)
    
    erb :lesson_player
  end
  
  # Instructor routes
  namespace '/instructor' do
    before do
      authenticate!
      halt 403 unless current_user.instructor?
    end
    
    get '/courses' do
      @courses = current_user.courses
      erb :'instructor/courses'
    end
    
    post '/courses' do
      @course = current_user.courses.build(course_params)
      
      if @course.save
        redirect "/instructor/courses/#{@course.slug}/edit"
      else
        @errors = @course.errors
        erb :'instructor/new_course'
      end
    end
    
    get '/courses/:slug/analytics' do
      @course = current_user.courses.find_by_slug!(params[:slug])
      @analytics = CourseAnalytics.new(@course)
      
      erb :'instructor/analytics'
    end
  end
  
  # API routes with versioning
  namespace '/api' do
    before do
      content_type :json
      
      # API authentication
      @api_key = request.env['HTTP_API_KEY'] || params[:api_key]
      @api_user = User.find_by_api_key(@api_key)
      
      halt 401, {error: 'Invalid API key'}.to_json unless @api_user
    end
    
    namespace '/v1' do
      get '/courses' do
        courses = Course.published.limit(100)
        courses.map(&:to_api_v1).to_json
      end
      
      get '/courses/:id' do
        course = Course.find(params[:id])
        course.to_api_v1.to_json
      end
    end
    
    namespace '/v2' do
      get '/courses' do
        courses = Course.published
        
        # V2 adds pagination
        page = (params[:page] || 1).to_i
        per_page = [(params[:per_page] || 20).to_i, 100].min
        
        courses = courses.page(page).per(per_page)
        
        {
          data: courses.map(&:to_api_v2),
          meta: {
            current_page: page,
            per_page: per_page,
            total_pages: courses.total_pages,
            total_count: courses.total_count
          }
        }.to_json
      end
    end
  end
  
  private
  
  def course_params
    params.slice(:title, :description, :price, :category_id)
  end
end
```

That's the power of Sinatra routing - simple enough to get started quickly, but flexible enough to handle complex production requirements. The key is understanding all the tools available and knowing when to use each one.
