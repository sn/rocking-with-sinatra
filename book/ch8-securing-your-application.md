# Chapter 8 - Securing Your Application

I've seen security treated as a final sprint before launch more times than I'd like to admit - and it almost always ends badly. You build the feature, it works, you ship it, and then six months later someone dumps your users table on Pastebin. With a course marketplace handling real user accounts, payment information & video content, that's not a situation you want to find yourself in. Fortunately Sinatra's ecosystem gives you everything you need to build something properly hardened, and it's honestly not as much work as you might think.

Between Rack's built-in protection middleware, Ruby's excellent bcrypt bindings, and the broader gem ecosystem, you have solid building blocks. This chapter walks through all of it.

## User Authentication

Authentication answers one question: who are you? For our course marketplace, we need users to sign up, log in, stay logged in across requests, and log out cleanly. I'll build this out using bcrypt & sessions, which gives you full control and is straightforward enough to understand completely.

### Using bcrypt for Password Hashing

Don't store plain-text passwords - seriously, I've seen what happens when this goes wrong, and it's not a fun conversation to have with your users. Don't store reversible encryption either. The correct approach is a one-way cryptographic hash using bcrypt, which is intentionally slow to make brute-force attacks impractical.

Add it to your Gemfile:

```ruby
gem 'bcrypt', '~> 3.1'
```

Your `User` model might look like this:

```ruby
class User < ActiveRecord::Base
  has_secure_password

  validates :email, presence: true, uniqueness: { case_sensitive: false }

  before_save { self.email = email.downcase.strip }
end
```

`has_secure_password` (from ActiveModel, included with ActiveRecord) does the heavy lifting for you. It adds `password` and `password_confirmation` virtual attributes, hashes the password into `password_digest` using BCrypt, and gives you an `authenticate` method that returns the user on success or `false` on failure. The BCrypt cost factor defaults to 12, meaning roughly 100ms per hash on a modern machine - slow enough to be a problem for attackers, fast enough to be invisible to real users.

You do need the `bcrypt` gem in your Gemfile for it to work:

### Session-Based Authentication

Sessions are how we remember that a user logged in. Sinatra uses Rack's cookie-based session store, which stores the session ID in a signed cookie on the client.

```ruby
class App < Sinatra::Base
  configure do
    enable :sessions
    set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(64) }
    set :sessions, httponly: true, secure: ENV['RACK_ENV'] == 'production', same_site: :lax
  end
end
```

Using `ENV.fetch` with a fallback to a random value means development works out of the box, but you're forced to set a real secret in production (more on this in the cookie security section). A missing `SESSION_SECRET` in production is a security hole, not a convenience.

### Login, Logout, and Signup Routes

Here is a complete set of auth routes for the course marketplace:

```ruby
class App < Sinatra::Base
  # Sign up
  get '/signup' do
    redirect '/dashboard' if logged_in?
    erb :'auth/signup'
  end

  post '/signup' do
    @user = User.new(
      email: params[:email],
      name: params[:name],
      password: params[:password]
    )

    if params[:password] != params[:password_confirmation]
      @error = 'Passwords do not match'
      return erb :'auth/signup'
    end

    if @user.save
      session[:user_id] = @user.id
      redirect '/dashboard'
    else
      @errors = @user.errors.full_messages
      erb :'auth/signup'
    end
  end

  # Log in
  get '/login' do
    redirect '/dashboard' if logged_in?
    erb :'auth/login'
  end

  post '/login' do
    @user = User.find_by(email: params[:email]&.downcase&.strip)

    if @user&.authenticate(params[:password])
      session[:user_id] = @user.id
      session[:logged_in_at] = Time.now.to_i

      return_to = params[:return_to]
      if return_to && return_to.start_with?('/')
        redirect return_to
      else
        redirect '/dashboard'
      end
    else
      @error = 'Invalid email or password'
      erb :'auth/login'
    end
  end

  # Log out
  delete '/logout' do
    session.clear
    redirect '/login'
  end

  # Also accept GET for simple logout links
  get '/logout' do
    session.clear
    redirect '/login'
  end
end
```

A few things worth noting here. I use `@user&.authenticate` rather than first checking if the user exists and then comparing the password - this prevents timing attacks that could reveal whether an email address is registered. We always take roughly the same amount of time to respond, regardless of whether the email was found.

The `return_to` redirect is important for usability - if someone tries to visit `/courses/123/learn` before logging in, you want to send them there after a successful login rather than dumping them on a generic dashboard. Notice the `start_with?('/')` check - without it, an attacker could craft a link like `/login?return_to=https://evil.com` and redirect your users off-site after they log in. Only redirect to paths that start with `/`, and you're safe.

### The current_user Helper

Rather than looking up the user on every route, I define a `current_user` helper that memoizes the result. Put this in your helpers file or in a `helpers` block:

```ruby
helpers do
  def current_user
    return nil unless session[:user_id]
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def logged_in?
    !current_user.nil?
  end

  def require_login!
    unless logged_in?
      session[:return_to] = request.path
      redirect '/login'
    end
  end

  def require_role!(role)
    require_login!
    halt 403, erb(:'errors/403') unless current_user.has_role?(role)
  end
end
```

The `@current_user` instance variable memoization matters here - within a single request, `current_user` might be called from the route handler, from a `before` filter, and from a view. You only want one database query, and the `||=` idiom makes sure that happens.

Use `require_login!` in your `before` filters for protected sections:

```ruby
before '/dashboard*' do
  require_login!
end

before '/instructor*' do
  require_login!
  halt 403 unless current_user.instructor?
end

before '/admin*' do
  require_login!
  halt 403 unless current_user.admin?
end
```

### Warden as an Alternative

For applications with complex authentication requirements - multiple user types, OAuth, API tokens & session auth all in the same app - I'd consider Warden instead of rolling your own.

Warden is Rack middleware that provides a clean framework for authentication strategies. It's what Devise is built on in Rails. Here's a quick taste:

```ruby
require 'warden'

use Warden::Manager do |manager|
  manager.default_strategies :password
  manager.failure_app = App
end

Warden::Strategies.add(:password) do
  def valid?
    params['email'] && params['password']
  end

  def authenticate!
    user = User.find_by(email: params['email'])
    if user&.authenticate(params['password'])
      success!(user)
    else
      fail!('Invalid email or password')
    end
  end
end
```

Warden is more to set up than the approach above, but it pays off when you need multiple concurrent authentication strategies. For most course marketplace applications, the manual approach covered in this chapter is perfectly sufficient.

## Rack::Protection

Before we write a single line of application security code, Rack's protection middleware is already doing a lot of work for us. For modular apps (`Sinatra::Base` subclasses), Sinatra includes `Rack::Protection` in all environments - not just production. Classic-style apps (using `require 'sinatra'`) also get it automatically. Either way, it's on by default, but it's worth being explicit in your own configuration so its presence is obvious to whoever reads the code next:

```ruby
class App < Sinatra::Base
  use Rack::Protection

  configure do
    enable :sessions
  end
end
```

`Rack::Protection` is actually a bundle of several independent middlewares that you can use individually or all at once.

### CSRF Protection

Cross-Site Request Forgery is an attack where a malicious website tricks a logged-in user's browser into making a request to your app. The classic example: a user is logged into your course marketplace, then visits a malicious site that silently submits a form to `/courses/purchase`.

`Rack::Protection::AuthenticityToken` handles this by requiring that forms include a secret token that only your server knows. Here's how to wire it up:

```ruby
class App < Sinatra::Base
  use Rack::Protection
  use Rack::Protection::AuthenticityToken

  configure do
    enable :sessions
    set :session_secret, ENV['SESSION_SECRET']
  end
end
```

In your form views, include the CSRF token:

```erb
<form method="POST" action="/courses/<%= @course.id %>/enroll">
  <input type="hidden" name="authenticity_token" value="<%= Rack::Protection::AuthenticityToken.token(session) %>">
  <button type="submit">Enroll Now</button>
</form>
```

To make this less painful, I add a helper - it's one of those things I reach for on every project:

```ruby
helpers do
  def csrf_token
    Rack::Protection::AuthenticityToken.token(session)
  end

  def csrf_tag
    "<input type=\"hidden\" name=\"authenticity_token\" value=\"#{csrf_token}\">"
  end
end
```

Then in your forms:

```erb
<form method="POST" action="/enroll">
  <%= csrf_tag %>
  <!-- rest of form -->
</form>
```

For AJAX requests, include the token as a header. Put this in your application JavaScript:

```javascript
// Read the token from a meta tag
const token = document.querySelector('meta[name="csrf-token"]').content;

fetch('/api/enroll', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-CSRF-Token': token
  },
  body: JSON.stringify({ course_id: courseId })
});
```

And in your layout:

```erb
<meta name="csrf-token" content="<%= csrf_token %>">
```

### XSS Protection

Cross-Site Scripting attacks happen when untrusted user input gets rendered in the browser as HTML or JavaScript. If someone stores `<script>alert('xss')</script>` as their username and you render it unescaped, their script runs in every browser that views it.

The primary defence is output escaping. ERB's `<%= %>` tags do **not** escape HTML by default in Sinatra - you must call `h()` or `ERB::Util.html_escape()` on every piece of user input yourself. `Rack::Protection::EscapedParams` can help, but don't rely on it as your only line of defence - and please don't use `<%== %>` (raw output) on user-supplied data, unless the world is ending.

```ruby
helpers do
  include ERB::Util
  alias_method :h, :html_escape
end
```

Then in your views:

```erb
<!-- Safe - h() escapes HTML entities -->
<h2><%= h(@course.title) %></h2>
<p>Instructor: <%= h(@instructor.name) %></p>

<!-- Dangerous - never do this with user input -->
<p><%== @user_bio %></p>
```

I also set a Content Security Policy header to give browsers an additional line of defence. Add this as a `before` filter or middleware:

```ruby
before do
  headers['Content-Security-Policy'] = [
    "default-src 'self'",
    "script-src 'self' https://cdn.jsdelivr.net",
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
    "img-src 'self' data: https:",
    "font-src 'self' https://fonts.gstatic.com",
    "connect-src 'self'",
    "frame-ancestors 'none'"
  ].join('; ')

  headers['X-Content-Type-Options'] = 'nosniff'
  headers['X-Frame-Options'] = 'DENY'
  headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
end
```

The `X-Content-Type-Options: nosniff` header prevents browsers from MIME-sniffing a response. The `X-Frame-Options: DENY` header prevents your pages from being embedded in iframes, which blocks clickjacking attacks.

## API Authentication

When you expose an API - say, to let instructors query their analytics programmatically or to support a mobile app - session cookies are not the right authentication mechanism. APIs use tokens.

### Using Authorization Headers

The standard way to pass an API token is the `Authorization` header, typically as a Bearer token:

```
Authorization: Bearer abc123tokenvalue
```

Here is how to read & validate it in Sinatra:

```ruby
helpers do
  def api_token
    auth_header = request.env['HTTP_AUTHORIZATION'] || ''
    auth_header.sub(/\ABearer\s+/, '')
  end

  def current_api_user
    return nil if api_token.blank?
    @current_api_user ||= User.find_by(api_token: api_token)
  end

  def require_api_auth!
    unless current_api_user
      halt 401, { error: 'Invalid or missing API token' }.to_json
    end
  end
end
```

Use it in your API routes:

```ruby
namespace '/api/v1' do
  before do
    content_type :json
    require_api_auth!
  end

  get '/courses' do
    courses = current_api_user.instructor? ? Course.all : Course.published
    courses.map(&:to_api_hash).to_json
  end

  get '/me' do
    {
      id: current_api_user.id,
      email: current_api_user.email,
      name: current_api_user.name,
      role: current_api_user.role
    }.to_json
  end
end
```

### Generating and Validating API Tokens

Tokens need to be unguessable & unique. The simplest approach:

```ruby
class User < ActiveRecord::Base
  before_create :generate_api_token

  def regenerate_api_token!
    update!(api_token: self.class.generate_secure_token)
  end

  def self.generate_secure_token
    SecureRandom.urlsafe_base64(32)
  end

  private

  def generate_api_token
    self.api_token ||= self.class.generate_secure_token
  end
end
```

Add a database index on `api_token` so lookups are fast:

```ruby
# In your migration
add_index :users, :api_token, unique: true
```

For higher-security scenarios, you can use HMAC-based token validation to avoid storing the token in the database at all. But for most applications, a random token stored as a secure hash is the right tradeoff between complexity & security.

If you want to store a hashed token instead (so that a database leak doesn't expose valid tokens), store `Digest::SHA256.hexdigest(token)` and give the user only the plain token once:

```ruby
class ApiToken < ActiveRecord::Base
  belongs_to :user

  def self.create_for(user)
    plain_token = SecureRandom.urlsafe_base64(32)
    token = create!(
      user: user,
      token_digest: Digest::SHA256.hexdigest(plain_token)
    )
    [token, plain_token]  # Return plain token to show the user ONCE
  end

  def self.authenticate(plain_token)
    digest = Digest::SHA256.hexdigest(plain_token)
    find_by(token_digest: digest)
  end
end
```

## OAuth Authentication

Building your own complete OAuth integration is non-trivial, but the `omniauth` gem makes adding social login straightforward. Here I'll add GitHub login to our marketplace, which is particularly useful for developer-focused courses.

Add to your Gemfile:

```ruby
gem 'omniauth', '~> 2.1'
gem 'omniauth-github', '~> 2.0'
```

Configure the middleware:

```ruby
require 'omniauth'
require 'omniauth-github'

class App < Sinatra::Base
  use OmniAuth::Builder do
    provider :github, ENV['GITHUB_CLIENT_ID'], ENV['GITHUB_CLIENT_SECRET'], scope: 'user:email'
  end
end
```

OmniAuth 2.x requires a POST request to `/auth/github` to kick off the flow - it no longer allows GET-initiated auth by default. That's a deliberate CSRF protection built into the library itself, so there's no separate CSRF middleware to wire up. Your login button should use a small form rather than a plain link:

Add a route to handle the OAuth callback:

```ruby
get '/auth/github/callback' do
  auth = request.env['omniauth.auth']

  # Find or create the user based on their GitHub ID
  @user = User.find_or_create_from_omniauth(auth)

  if @user
    session[:user_id] = @user.id
    redirect '/dashboard'
  else
    redirect '/login?error=oauth_failed'
  end
end

get '/auth/failure' do
  @error = params[:message]
  erb :'auth/failure'
end
```

In your `User` model:

```ruby
class User < ActiveRecord::Base
  def self.find_or_create_from_omniauth(auth)
    user = find_or_initialize_by(
      provider: auth['provider'],
      uid: auth['uid']
    )

    user.assign_attributes(
      email: auth.dig('info', 'email'),
      name: auth.dig('info', 'name'),
      avatar_url: auth.dig('info', 'image')
    )

    # OAuth users do not have a local password - set a random one so
    # has_secure_password's presence validation passes
    user.password = SecureRandom.hex(32) unless user.persisted?

    user.save ? user : nil
  end
end
```

In your views, add a login button. Because OmniAuth 2.x requires a POST, use a form rather than a plain anchor link:

```erb
<form method="POST" action="/auth/github">
  <input type="hidden" name="authenticity_token" value="<%= csrf_token %>">
  <button type="submit" class="btn btn-dark">Sign in with GitHub</button>
</form>
```

OmniAuth handles the redirect to GitHub, the token exchange, and the callback - you just handle what to do with the user data you receive. The same pattern works for Google, Twitter, or any of the dozens of OmniAuth strategy gems available.

## Input Validation

Every piece of data that comes from the outside world is untrusted - params from forms, JSON request bodies, URL parameters, HTTP headers, all of it needs to be validated before you act on it or store it. I found building this habit early makes the rest of the security work much easier.

### Manual Validation

For most use cases in Sinatra, a simple validation approach in your route handler is clean & easy to follow:

```ruby
post '/courses' do
  require_login!

  errors = []

  errors << 'Title is required' if params[:title].to_s.strip.empty?
  errors << 'Title must be under 200 characters' if params[:title].to_s.length > 200
  errors << 'Price must be a positive number' unless params[:price].to_s.match?(/\A\d+(\.\d{1,2})?\z/)
  errors << 'Category is required' if params[:category_id].to_s.empty?

  unless errors.empty?
    @errors = errors
    @course = Course.new(params.slice(:title, :description, :price, :category_id))
    return erb :'courses/new'
  end

  @course = current_user.courses.build(
    title: params[:title].strip,
    description: params[:description].to_s.strip,
    price: params[:price].to_f.round(2),
    category_id: params[:category_id].to_i
  )

  if @course.save
    redirect "/instructor/courses/#{@course.id}/edit"
  else
    @errors = @course.errors.full_messages
    erb :'courses/new'
  end
end
```

For API routes where you want structured parameter checking, the `sinatra-param` gem is handy:

```ruby
gem 'sinatra-param'
```

```ruby
require 'sinatra/param'

class App < Sinatra::Base
  helpers Sinatra::Param

  post '/api/v1/courses' do
    param :title,       String,  required: true, max_length: 200
    param :price,       Float,   required: true, min: 0, max: 9999
    param :category_id, Integer, required: true

    @course = current_api_user.courses.create!(
      title: params[:title],
      price: params[:price],
      category_id: params[:category_id]
    )

    status 201
    @course.to_json
  rescue Sinatra::Param::InvalidParameterError => e
    halt 422, { error: e.message }.to_json
  end
end
```

### Protecting Against SQL Injection

If you are using ActiveRecord, parameterized queries protect you from SQL injection as long as you use the proper methods - the key rule is to never interpolate user input directly into a query string.

```ruby
# DANGEROUS - never do this
Course.where("title = '#{params[:title]}'")

# Safe - parameterized query
Course.where('title = ?', params[:title])

# Also safe - hash conditions
Course.where(title: params[:title])

# Safe - named parameters
Course.where('title = :title AND price <= :max_price',
             title: params[:title],
             max_price: params[:max_price].to_f)
```

For full-text search where you need to build more complex queries, I'd use `Arel` or a library like `pg_search` rather than assembling SQL strings:

```ruby
# Using pg_search
class Course < ActiveRecord::Base
  include PgSearch::Model

  pg_search_scope :search_by_title_and_description,
    against: [:title, :description],
    using: {
      tsearch: { prefix: true }
    }
end

# In your route
get '/courses/search' do
  @query = params[:q].to_s.strip
  @courses = @query.length >= 2 ? Course.search_by_title_and_description(@query) : Course.none
  erb :'courses/search'
end
```

### Sanitizing HTML Input

If your course descriptions allow rich text input (for formatting course content), you need to sanitize the HTML before storing or rendering it. The `sanitize-html` concept from Node.js has a Ruby equivalent in the `sanitize` gem:

```ruby
gem 'sanitize'
```

```ruby
require 'sanitize'

class Course < ActiveRecord::Base
  ALLOWED_ELEMENTS = %w[p br strong em ul ol li h2 h3 h4 blockquote code pre].freeze
  ALLOWED_ATTRIBUTES = { 'a' => ['href', 'title'] }.freeze

  before_save :sanitize_description

  private

  def sanitize_description
    return if description.blank?
    self.description = Sanitize.fragment(
      description,
      elements: ALLOWED_ELEMENTS,
      attributes: ALLOWED_ATTRIBUTES,
      remove_contents: %w[script style]
    )
  end
end
```

This strips any tags not in the allow list, removing `<script>`, `<iframe>`, event handlers, and anything else an attacker might try to inject.

## Cookie Security

Session cookies are a high-value target for attackers - if someone can steal your session cookie, they can log in as you. Getting the session configuration right closes off several attack vectors, and it's one of those things that's easy to set up correctly from the start.

Here is a production-appropriate session configuration:

```ruby
class App < Sinatra::Base
  use Rack::Session::Cookie,
    key: '_course_marketplace_session',
    path: '/',
    expire_after: 86_400 * 14,   # 14 days
    secret: ENV.fetch('SESSION_SECRET'),
    httponly: true,
    secure: ENV['RACK_ENV'] == 'production',
    same_site: :lax
end
```

Breaking down the important options:

`httponly: true` - This prevents JavaScript from reading the cookie. If an XSS vulnerability exists, the attacker cannot steal the session cookie via `document.cookie`. This is one of the most impactful security settings you can set.

`secure: true` (in production) - Instructs the browser to only send the cookie over HTTPS connections. A cookie without this flag can be intercepted on any HTTP request - including redirects before HTTPS kicks in.

`same_site: :lax` - Prevents the browser from sending the cookie on cross-site requests. This provides CSRF protection at the browser level, in addition to the token-based protection from `Rack::Protection`. Use `:strict` if your app never needs to work when linked from other sites (this breaks things like links from emails that trigger logged-in actions). Use `:none` only if you specifically need cross-site cookie access & you have other CSRF mitigations in place.

`expire_after` - How long before the cookie expires in the browser. 14 days is a reasonable balance between security (short session lifetimes) and usability (users don't want to log in every day). For an admin panel, I'd make this much shorter.

For the session secret, use at least 64 random bytes:

```ruby
# Generate a strong secret - run this once and store the result in your env
require 'securerandom'
puts SecureRandom.hex(64)
```

Store it in your environment, never in your code:

```bash
# .env (never commit this file)
SESSION_SECRET=a94a8fe5ccb19ba61c4c0873d391e987982fbbd3...
```

If you ever suspect your session secret has been compromised, change it immediately. All existing sessions will be invalidated, which means all users will be logged out - and that's the correct outcome.

## SSL/HTTPS in Production

Running your application over HTTP in production isn't something I'd ever ship - all data, including session cookies, passwords & payment details, travels in plain text over HTTP and can be intercepted. HTTPS encrypts the connection between the browser and your server.

### Forcing HTTPS

Force all traffic to HTTPS by redirecting HTTP requests in Sinatra:

```ruby
class App < Sinatra::Base
  configure :production do
    before do
      unless request.secure?
        redirect "https://#{request.host}#{request.fullpath}", 301
      end
    end

    # Tell browsers to always use HTTPS for this domain
    after do
      headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
    end
  end
end
```

The `Strict-Transport-Security` header (HSTS) tells the browser to always use HTTPS for this domain for the next year, even if the user types `http://`. This protects against SSL stripping attacks.

### Nginx Configuration with Let's Encrypt

In production, you'll typically run Sinatra behind Nginx, which handles SSL termination. Here is a basic Nginx configuration using Let's Encrypt certificates (obtained via `certbot`):

```nginx
server {
    listen 80;
    server_name courses.example.com;

    # Let's Encrypt challenge
    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }

    # Redirect all HTTP to HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name courses.example.com;

    ssl_certificate     /etc/letsencrypt/live/courses.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/courses.example.com/privkey.pem;

    # Modern SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    location / {
        proxy_pass http://127.0.0.1:9292;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Get your certificate with certbot:

```bash
sudo certbot --nginx -d courses.example.com
```

Certbot will handle automatic renewal. Run `sudo certbot renew --dry-run` to verify the renewal process works before your certificate expires.

Tell your Sinatra app it is behind a proxy so `request.secure?` returns the right value:

```ruby
class App < Sinatra::Base
  configure :production do
    # Trust the X-Forwarded-Proto header from Nginx
    before do
      env['rack.url_scheme'] = 'https' if env['HTTP_X_FORWARDED_PROTO'] == 'https'
    end
  end
end
```

## Example: Building Authentication Flows

Let's bring everything together into a complete, production-ready authentication system for the course marketplace. This covers signup, login, logout & password reset with a secure time-limited token.

### The Database Schema

Start with a migration:

```ruby
class CreateUsers < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      t.string :email,            null: false
      t.string :name,             null: false
      t.string :password_digest,  null: false
      t.string :role,             null: false, default: 'student'
      t.string :api_token
      t.string :reset_token_digest
      t.datetime :reset_token_expires_at
      t.datetime :last_sign_in_at
      t.string :last_sign_in_ip
      t.timestamps
    end

    add_index :users, :email,     unique: true
    add_index :users, :api_token, unique: true
    add_index :users, :reset_token_digest
  end
end
```

### The User Model

```ruby
require 'securerandom'
require 'digest'

class User < ActiveRecord::Base
  has_secure_password

  ROLES = %w[student instructor admin].freeze

  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name,  presence: true, length: { maximum: 100 }
  validates :role,  inclusion: { in: ROLES }
  validates :password, length: { minimum: 8 }, allow_nil: true

  before_save { self.email = email.downcase.strip }
  before_create :generate_api_token

  def instructor?
    role == 'instructor'
  end

  def admin?
    role == 'admin'
  end

  # Password reset

  def generate_reset_token!
    plain_token = SecureRandom.urlsafe_base64(32)
    update!(
      reset_token_digest: Digest::SHA256.hexdigest(plain_token),
      reset_token_expires_at: 1.hour.from_now
    )
    plain_token
  end

  def self.find_by_reset_token(plain_token)
    digest = Digest::SHA256.hexdigest(plain_token)
    user = find_by(reset_token_digest: digest)
    return nil unless user
    return nil if user.reset_token_expires_at < Time.now
    user
  end

  def clear_reset_token!
    update!(
      reset_token_digest: nil,
      reset_token_expires_at: nil
    )
  end

  def record_sign_in!(ip:)
    update!(
      last_sign_in_at: Time.now,
      last_sign_in_ip: ip
    )
  end

  private

  def generate_api_token
    self.api_token ||= SecureRandom.urlsafe_base64(32)
  end
end
```

### The Auth Controller

In a modular app, I put auth routes in their own controller file:

```ruby
# controllers/auth_controller.rb
class AuthController < Sinatra::Base
  helpers AuthHelpers

  # --- Signup ---

  get '/signup' do
    redirect '/dashboard' if logged_in?
    erb :'auth/signup'
  end

  post '/signup' do
    redirect '/dashboard' if logged_in?

    if params[:password] != params[:password_confirmation]
      @error = 'Passwords do not match'
      return erb :'auth/signup'
    end

    @user = User.new(
      email: params[:email].to_s.strip,
      name: params[:name].to_s.strip,
      password: params[:password],
      role: 'student'
    )

    if @user.save
      session[:user_id] = @user.id
      UserMailer.welcome(@user).deliver_now
      redirect '/dashboard'
    else
      @errors = @user.errors.full_messages
      erb :'auth/signup'
    end
  end

  # --- Login ---

  get '/login' do
    redirect '/dashboard' if logged_in?
    erb :'auth/login'
  end

  post '/login' do
    @user = User.find_by(email: params[:email].to_s.downcase.strip)

    if @user&.authenticate(params[:password].to_s)
      session[:user_id] = @user.id
      @user.record_sign_in!(ip: request.ip)

      return_to = session.delete(:return_to) || '/dashboard'
      redirect return_to
    else
      @error = 'Invalid email or password'
      erb :'auth/login'
    end
  end

  # --- Logout ---

  get '/logout' do
    session.clear
    redirect '/login'
  end

  # --- Forgot Password ---

  get '/forgot-password' do
    erb :'auth/forgot_password'
  end

  post '/forgot-password' do
    @user = User.find_by(email: params[:email].to_s.downcase.strip)

    # Always show the same success message to prevent user enumeration
    if @user
      plain_token = @user.generate_reset_token!
      reset_url = "#{request.base_url}/reset-password/#{plain_token}"
      UserMailer.password_reset(@user, reset_url).deliver_now
    end

    @message = 'If that email address is in our system, you will receive a password reset link shortly.'
    erb :'auth/forgot_password_sent'
  end

  # --- Reset Password ---

  get '/reset-password/:token' do
    @user = User.find_by_reset_token(params[:token])
    halt 404, erb(:'auth/invalid_reset_token') unless @user

    @token = params[:token]
    erb :'auth/reset_password'
  end

  post '/reset-password/:token' do
    @user = User.find_by_reset_token(params[:token])
    halt 404, erb(:'auth/invalid_reset_token') unless @user

    if params[:password] != params[:password_confirmation]
      @error = 'Passwords do not match'
      @token = params[:token]
      return erb :'auth/reset_password'
    end

    @user.password = params[:password]

    if @user.save
      @user.clear_reset_token!
      session[:user_id] = @user.id
      redirect '/dashboard?notice=password_updated'
    else
      @error = @user.errors.full_messages.first
      @token = params[:token]
      erb :'auth/reset_password'
    end
  end
end
```

### The Auth Helpers Module

```ruby
# helpers/auth_helpers.rb
module AuthHelpers
  def current_user
    return nil unless session[:user_id]
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def logged_in?
    !current_user.nil?
  end

  def require_login!
    unless logged_in?
      session[:return_to] = request.path_info
      redirect '/login'
    end
  end

  def require_instructor!
    require_login!
    halt 403, erb(:'errors/403') unless current_user.instructor? || current_user.admin?
  end

  def require_admin!
    require_login!
    halt 403, erb(:'errors/403') unless current_user.admin?
  end
end
```

### Wiring It Up

In `config.ru`:

```ruby
require 'sinatra/base'
require 'rack'

require_relative 'app'
require_relative 'controllers/auth_controller'

use Rack::Session::Cookie,
  key: '_marketplace_session',
  secret: ENV.fetch('SESSION_SECRET'),
  expire_after: 86_400 * 14,
  httponly: true,
  secure: ENV['RACK_ENV'] == 'production',
  same_site: :lax

use Rack::Protection
use AuthController

run App
```

In `app.rb`:

```ruby
require 'sinatra/base'
require_relative 'helpers/auth_helpers'
require_relative 'models/user'

class App < Sinatra::Base
  helpers AuthHelpers

  before '/dashboard*' do
    require_login!
  end

  before '/instructor*' do
    require_instructor!
  end

  before '/admin*' do
    require_admin!
  end

  get '/' do
    erb :home
  end

  get '/dashboard' do
    @recent_courses = current_user.enrolled_courses.limit(5)
    erb :dashboard
  end
end
```

### The Login View

```erb
<!-- views/auth/login.erb -->
<div class="auth-container">
  <h1>Welcome back</h1>

  <% if @error %>
    <div class="alert alert-error"><%= h(@error) %></div>
  <% end %>

  <form method="POST" action="/login">
    <input type="hidden" name="authenticity_token" value="<%= csrf_token %>">

    <div class="form-group">
      <label for="email">Email address</label>
      <input type="email" id="email" name="email"
             value="<%= h(params[:email].to_s) %>"
             required autocomplete="email">
    </div>

    <div class="form-group">
      <label for="password">Password</label>
      <input type="password" id="password" name="password"
             required autocomplete="current-password">
    </div>

    <button type="submit" class="btn btn-primary">Sign in</button>
  </form>

  <p>
    <a href="/forgot-password">Forgot your password?</a> &middot;
    <a href="/signup">Create an account</a>
  </p>
</div>
```

### The Password Reset Email

You'll need a mailer to send the reset link. If you are using ActionMailer standalone:

```ruby
# mailers/user_mailer.rb
require 'action_mailer'

ActionMailer::Base.smtp_settings = {
  address: ENV['SMTP_HOST'],
  port: 587,
  user_name: ENV['SMTP_USERNAME'],
  password: ENV['SMTP_PASSWORD'],
  authentication: 'plain',
  enable_starttls_auto: true
}

class UserMailer < ActionMailer::Base
  default from: 'noreply@courses.example.com'

  def welcome(user)
    @user = user
    mail(to: user.email, subject: 'Welcome to the course marketplace')
  end

  def password_reset(user, reset_url)
    @user = user
    @reset_url = reset_url
    mail(to: user.email, subject: 'Reset your password')
  end
end
```

And a plain text email template:

```
# views/user_mailer/password_reset.text.erb
Hi <%= @user.name %>,

Someone requested a password reset for your account. If this was you,
click the link below to set a new password:

<%= @reset_url %>

This link expires in 1 hour.

If you did not request a password reset, you can safely ignore this email.
Your password will not change unless you click the link above.

- The Course Marketplace Team
```

That's a complete, production-quality authentication system - it handles the common cases cleanly, avoids the most common security mistakes, and gives you a foundation to extend as your application grows.

Security is never done, it's a practice. I'd recommend keeping your dependencies up to date, watching the CVE feeds for gems you depend on, and running something like `bundler-audit` in your CI pipeline to catch known vulnerabilities automatically:

```bash
gem install bundler-audit
bundle audit check --update
```

The next chapter covers building out a public-facing API on top of this authentication foundation.
