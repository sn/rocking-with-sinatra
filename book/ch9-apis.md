# Chapter 9 - All About APIs

At some point every serious web application needs to talk to the outside world - and be talked to back. Payment processors, mobile clients, third-party integrations, instructor tooling - they all need an API. I've found Sinatra genuinely well-suited for this kind of work because it gets completely out of your way and lets you structure things exactly how you need them. In this chapter I'll show you how I'd build a complete API layer for our course marketplace, consume external services, and we'll even touch on GraphQL for good measure.

## Basic REST API Principles

REST gets thrown around a lot but it's really just a set of architectural constraints that, when followed, produce APIs that are predictable and easy to work with. The core idea is that you model your application as a collection of resources & interact with those resources using standard HTTP methods.

For our course marketplace the resources are things like courses, lessons, enrollments & users. Each resource has a URL, and you perform operations on it using the right HTTP verb.

| Method | What it means |
| ------ | ------------- |
| GET    | Fetch a resource or collection |
| POST   | Create a new resource |
| PUT    | Replace a resource entirely |
| PATCH  | Partially update a resource |
| DELETE | Remove a resource |

Status codes are equally important - please don't return a 200 OK with an error message buried in the JSON body. Use the right code:

| Code | Meaning |
| ---- | ------- |
| 200  | OK - request succeeded |
| 201  | Created - new resource was made |
| 204  | No Content - success, nothing to return |
| 400  | Bad Request - malformed or invalid input |
| 401  | Unauthorized - not authenticated |
| 403  | Forbidden - authenticated but not allowed |
| 404  | Not Found |
| 409  | Conflict - e.g., duplicate enrollment |
| 422  | Unprocessable Entity - validation failed |
| 429  | Too Many Requests - rate limited |
| 500  | Internal Server Error |

### Structuring Requests

I generally find that keeping URL structure logical & consistent saves a lot of pain down the road. Nest resources to show ownership, keep collections plural, and use IDs or slugs to identify individual records.

```
GET  /api/v1/courses              # list courses
POST /api/v1/courses              # create a course
GET  /api/v1/courses/:id          # get a course
PATCH /api/v1/courses/:id         # update a course
DELETE /api/v1/courses/:id        # delete a course

GET  /api/v1/courses/:id/lessons  # list lessons for a course
POST /api/v1/courses/:id/lessons  # add a lesson to a course

GET  /api/v1/enrollments          # list my enrollments
POST /api/v1/enrollments          # enroll in a course
```

Query parameters handle filtering, sorting & pagination - they don't belong in the path:

```
GET /api/v1/courses?category=programming&sort=popular&page=2&per_page=20
```

Request bodies for POST and PATCH should be JSON. Clients need to send a `Content-Type: application/json` header, and I'd validate this on the server side:

```ruby
before do
  if request.post? || request.patch? || request.put?
    unless request.content_type&.include?('application/json')
      halt 415, { error: 'Content-Type must be application/json' }.to_json
    end
  end
end
```

### Versioning

APIs change - I can guarantee you that. You'll add fields, rename things, change behaviour. Clients written against your original API will break if you change it under them. Versioning gives you the freedom to evolve without breaking existing integrations.

There are two main approaches.

**URL-based versioning** is the most common and the most visible:

```
/api/v1/courses
/api/v2/courses
```

It's explicit, easy to test in a browser & simple to understand. The downside is that URLs are supposed to identify resources, not API versions - but in practice this matters less than keeping your clients happy.

**Header-based versioning** uses an `Accept` header:

```
Accept: application/vnd.coursemarket.v2+json
```

This is more RESTfully pure but requires clients to set headers correctly and makes the API harder to explore manually. I'd go with URL-based versioning for most applications - it's just less friction for everyone involved.

In Sinatra, URL versioning is clean because you can mount separate classes for each version:

```ruby
# config.ru
require_relative 'app'
require_relative 'api/v1/api'
require_relative 'api/v2/api'

map '/api/v1' do
  run API::V1::App
end

map '/api/v2' do
  run API::V2::App
end

map '/' do
  run App
end
```

### Error Handling

Consistent error responses are a gift to everyone who uses your API - including future you (doesn't every project eventually have a future you?). Pick a format and stick to it across every endpoint.

A simple format that works well:

```json
{
  "error": {
    "code": "validation_failed",
    "message": "The request could not be processed",
    "details": [
      "Title can't be blank",
      "Price must be greater than 0"
    ]
  }
}
```

In Sinatra, I centralise this with error handlers and a helper method:

```ruby
class BaseAPI < Sinatra::Base
  helpers do
    def api_error(code, message, status_code, details: nil)
      halt status_code, {
        error: {
          code: code,
          message: message,
          details: details
        }.compact
      }.to_json
    end
  end

  error 404 do
    content_type :json
    { error: { code: 'not_found', message: 'The requested resource does not exist' } }.to_json
  end

  error 500 do
    content_type :json
    { error: { code: 'internal_error', message: 'An unexpected error occurred' } }.to_json
  end

  not_found do
    content_type :json
    { error: { code: 'not_found', message: 'The requested resource does not exist' } }.to_json
  end
end
```

Now every error response in the API looks the same, regardless of where it originated - which makes life much easier for anyone consuming the API.

---

## Creating a JSON API Service

Let's build the actual API for our course marketplace. I'll start with a base class that handles the cross-cutting concerns - content type, authentication & error formatting - then build specific resource endpoints on top of it.

### The Base API Class

```ruby
# api/base.rb
require 'sinatra/base'
require 'json'

module API
  class Base < Sinatra::Base
    before do
      content_type :json
      authenticate_request!
      parse_json_body
    end

    helpers do
      def authenticate_request!
        token = extract_token
        @current_user = User.find_by(api_token: token)
        halt 401, { error: { code: 'unauthorized', message: 'Invalid or missing API token' } }.to_json unless @current_user
      end

      def extract_token
        auth_header = request.env['HTTP_AUTHORIZATION']
        if auth_header&.start_with?('Bearer ')
          auth_header.split(' ', 2).last
        else
          params[:api_token]
        end
      end

      def parse_json_body
        raw = request.body.read
        request.body.rewind
        return if raw.nil? || raw.empty?
        @json_body = JSON.parse(raw, symbolize_names: true)
      rescue JSON::ParserError
        halt 400, { error: { code: 'invalid_json', message: 'Request body is not valid JSON' } }.to_json
      end

      def json_body
        @json_body || {}
      end

      def current_user
        @current_user
      end

      def paginate(scope)
        page     = [params.fetch(:page, 1).to_i, 1].max
        per_page = [[params.fetch(:per_page, 20).to_i, 1].max, 100].min

        {
          data:  scope.limit(per_page).offset((page - 1) * per_page),
          meta:  {
            page:       page,
            per_page:   per_page,
            total:      scope.count
          }
        }
      end

      def api_error(code, message, status_code, details: nil)
        halt status_code, {
          error: {
            code:    code,
            message: message,
            details: details
          }.compact
        }.to_json
      end

      def require_params!(*keys)
        missing = keys.reject { |k| json_body.key?(k) }
        unless missing.empty?
          api_error(
            'missing_parameters',
            "Required parameters missing: #{missing.join(', ')}",
            400
          )
        end
      end
    end

    error 404 do
      content_type :json
      { error: { code: 'not_found', message: 'Resource not found' } }.to_json
    end

    error 500 do
      content_type :json
      { error: { code: 'internal_error', message: 'An unexpected error occurred' } }.to_json
    end

    not_found do
      content_type :json
      { error: { code: 'not_found', message: 'Route not found' } }.to_json
    end
  end
end
```

### CRUD Endpoints for Courses

```ruby
# api/v1/courses.rb
module API
  module V1
    class Courses < API::Base
      # GET /courses
      get '/' do
        scope = Course.published

        scope = scope.where(category: params[:category]) if params[:category]
        scope = scope.where('title ILIKE ?', "%#{params[:q]}%") if params[:q]

        scope = case params[:sort]
                when 'newest'    then scope.order(created_at: :desc)
                when 'price_asc' then scope.order(price: :asc)
                else scope.order(enrollments_count: :desc)
                end

        result = paginate(scope)

        {
          data: result[:data].map(&:to_api_hash),
          meta: result[:meta]
        }.to_json
      end

      # GET /courses/:id
      get '/:id' do
        course = Course.find_by(id: params[:id])
        api_error('not_found', 'Course not found', 404) unless course

        course.to_api_hash.to_json
      end

      # POST /courses
      post '/' do
        unless current_user.instructor?
          api_error('forbidden', 'Only instructors can create courses', 403)
        end

        require_params!(:title, :description, :price)

        course = current_user.courses.build(
          title:       json_body[:title],
          description: json_body[:description],
          price:       json_body[:price].to_f,
          category:    json_body[:category]
        )

        if course.save
          status 201
          course.to_api_hash.to_json
        else
          api_error('validation_failed', 'Course could not be saved', 422, details: course.errors.full_messages)
        end
      end

      # PATCH /courses/:id
      patch '/:id' do
        course = current_user.courses.find_by(id: params[:id])
        api_error('not_found', 'Course not found', 404) unless course

        allowed = %i[title description price category published]
        attrs   = json_body.slice(*allowed)

        if course.update(attrs)
          course.to_api_hash.to_json
        else
          api_error('validation_failed', 'Course could not be updated', 422, details: course.errors.full_messages)
        end
      end

      # DELETE /courses/:id
      delete '/:id' do
        course = current_user.courses.find_by(id: params[:id])
        api_error('not_found', 'Course not found', 404) unless course

        course.destroy
        status 204
      end
    end
  end
end
```

Notice that all error responses go through `api_error` which calls `halt`. That means there's no need to guard with `if/else` after every check - `halt` exits the block immediately, which keeps the happy path clean.

### Lessons Endpoints

```ruby
# api/v1/lessons.rb
module API
  module V1
    class Lessons < API::Base
      # GET /courses/:course_id/lessons
      get '/' do
        course = Course.find_by(id: params[:course_id])
        api_error('not_found', 'Course not found', 404) unless course

        enrolled = current_user.enrolled_in?(course) || current_user.owns?(course)

        lessons = enrolled ? course.lessons.ordered : course.lessons.free.ordered

        { data: lessons.map(&:to_api_hash) }.to_json
      end

      # GET /courses/:course_id/lessons/:id
      get '/:id' do
        course = Course.find_by(id: params[:course_id])
        api_error('not_found', 'Course not found', 404) unless course

        lesson = course.lessons.find_by(id: params[:id])
        api_error('not_found', 'Lesson not found', 404) unless lesson

        unless lesson.free? || current_user.enrolled_in?(course) || current_user.owns?(course)
          api_error('forbidden', 'You must be enrolled to access this lesson', 403)
        end

        lesson.to_api_hash.to_json
      end

      # POST /courses/:course_id/lessons
      post '/' do
        course = current_user.courses.find_by(id: params[:course_id])
        api_error('not_found', 'Course not found or not owned by you', 404) unless course

        require_params!(:title, :position)

        lesson = course.lessons.build(
          title:       json_body[:title],
          description: json_body[:description],
          video_url:   json_body[:video_url],
          position:    json_body[:position].to_i,
          free:        json_body.fetch(:free, false)
        )

        if lesson.save
          status 201
          lesson.to_api_hash.to_json
        else
          api_error('validation_failed', 'Lesson could not be saved', 422, details: lesson.errors.full_messages)
        end
      end
    end
  end
end
```

### Enrollments Endpoint

```ruby
# api/v1/enrollments.rb
module API
  module V1
    class Enrollments < API::Base
      # GET /enrollments
      get '/' do
        enrollments = current_user.enrollments.includes(:course).recent

        {
          data: enrollments.map do |enrollment|
            {
              id:          enrollment.id,
              course:      enrollment.course.to_api_hash,
              enrolled_at: enrollment.created_at.iso8601,
              progress:    enrollment.progress_percentage
            }
          end
        }.to_json
      end

      # POST /enrollments
      post '/' do
        require_params!(:course_id)

        course = Course.published.find_by(id: json_body[:course_id])
        api_error('not_found', 'Course not found', 404) unless course

        if current_user.enrolled_in?(course)
          api_error('conflict', 'Already enrolled in this course', 409)
        end

        enrollment = current_user.enrollments.build(course: course)

        if course.paid?
          api_error('payment_required', 'Use the checkout endpoint to enroll in paid courses', 402)
        end

        if enrollment.save
          status 201
          {
            id:          enrollment.id,
            course_id:   course.id,
            enrolled_at: enrollment.created_at.iso8601
          }.to_json
        else
          api_error('validation_failed', 'Enrollment failed', 422, details: enrollment.errors.full_messages)
        end
      end

      # DELETE /enrollments/:id
      delete '/:id' do
        enrollment = current_user.enrollments.find_by(id: params[:id])
        api_error('not_found', 'Enrollment not found', 404) unless enrollment

        enrollment.destroy
        status 204
      end
    end
  end
end
```

### Mounting the API

I bring all the pieces together in `config.ru`. Using `Rack::Builder` and `map` blocks keeps everything clean:

```ruby
# api/v1/app.rb
require_relative '../base'
require_relative 'courses'
require_relative 'lessons'
require_relative 'enrollments'

module API
  module V1
    App = Rack::Builder.new do
      map '/courses' do
        run Courses
      end

      map '/courses' do
        run Lessons
      end

      map '/enrollments' do
        run Enrollments
      end
    end
  end
end
```

```ruby
# config.ru
require_relative 'app'
require_relative 'api/v1/app'

map '/api/v1' do
  run API::V1::App
end

map '/' do
  run App
end
```

### Pagination in API Responses

The `paginate` helper in the base class handles the mechanics, but the response format matters too. Clients need enough information to build pagination UI & to know when they've reached the last page:

```json
{
  "data": [...],
  "meta": {
    "page": 2,
    "per_page": 20,
    "total": 143
  },
  "links": {
    "self":  "/api/v1/courses?page=2&per_page=20",
    "first": "/api/v1/courses?page=1&per_page=20",
    "prev":  "/api/v1/courses?page=1&per_page=20",
    "next":  "/api/v1/courses?page=3&per_page=20",
    "last":  "/api/v1/courses?page=8&per_page=20"
  }
}
```

I'd add a `pagination_links` helper to the base class:

```ruby
def pagination_links(scope_count, page, per_page)
  total_pages = (scope_count.to_f / per_page).ceil
  base        = "#{request.path}?per_page=#{per_page}"

  links = {
    self:  "#{base}&page=#{page}",
    first: "#{base}&page=1",
    last:  "#{base}&page=#{total_pages}"
  }

  links[:prev] = "#{base}&page=#{page - 1}" if page > 1
  links[:next] = "#{base}&page=#{page + 1}" if page < total_pages

  links
end
```

---

## API Authentication

The base class already validates tokens, but it's worth thinking through how those tokens are generated & managed in the first place.

### Generating API Keys

I'd keep this simple. A sufficiently random token stored against the user record is all you need for most applications:

```ruby
# models/user.rb
class User < ActiveRecord::Base
  before_create :generate_api_token

  def rotate_api_token!
    update!(api_token: self.class.generate_secure_token)
  end

  def self.generate_secure_token
    SecureRandom.urlsafe_base64(32)
  end

  private

  def generate_api_token
    self.api_token = self.class.generate_secure_token
  end
end
```

Then add an endpoint so users can retrieve and rotate their token:

```ruby
# api/v1/tokens.rb
module API
  module V1
    class Tokens < API::Base
      # GET /token  -- return current token (already authenticated)
      get '/' do
        { api_token: current_user.api_token }.to_json
      end

      # POST /token/rotate
      post '/rotate' do
        current_user.rotate_api_token!
        { api_token: current_user.api_token }.to_json
      end
    end
  end
end
```

I'd store tokens hashed in the database if your security requirements demand it - the same way you'd store passwords. For most SaaS applications, plain tokens with TLS are acceptable, but financial or healthcare data warrants hashing with BCrypt or similar.

### Validating Tokens in Before Filters

The `authenticate_request!` method in the base class runs before every request. That's fine for private APIs, but what if some endpoints need to be public?

I'd override the before filter and skip authentication selectively:

```ruby
module API
  class Base < Sinatra::Base
    set :public_routes, []

    before do
      content_type :json
      parse_json_body
      authenticate_request! unless public_route?
    end

    helpers do
      def public_route?
        self.class.settings.public_routes.any? do |pattern|
          File.fnmatch?(pattern, request.path_info)
        end
      end
    end
  end
end

# In your courses endpoint, allow public listing:
module API
  module V1
    class Courses < API::Base
      set :public_routes, ['/', '/*']

      get '/' do
        # No auth required - public course listing
        Course.published.limit(20).map(&:to_api_hash).to_json
      end
    end
  end
end
```

### Rate Limiting Basics

Rate limiting protects your API from abuse & ensures fair usage. A Redis-backed token bucket is the standard approach. Here's a straightforward implementation using Redis's INCR and EXPIRE commands:

```ruby
# lib/rate_limiter.rb
class RateLimiter
  attr_reader :limit

  def initialize(redis, limit:, window:)
    @redis  = redis
    @limit  = limit
    @window = window  # seconds
  end

  def check!(identifier)
    key   = "rate_limit:#{identifier}"
    count = @redis.incr(key)

    @redis.expire(key, @window) if count == 1

    if count > @limit
      reset_at = @redis.ttl(key)
      raise RateLimitExceeded.new(
        limit:    @limit,
        reset_in: reset_at
      )
    end

    { remaining: @limit - count, reset_in: @redis.ttl(key) }
  end
end

class RateLimitExceeded < StandardError
  attr_reader :limit, :reset_in

  def initialize(limit:, reset_in:)
    @limit    = limit
    @reset_in = reset_in
    super("Rate limit of #{limit} requests exceeded")
  end
end
```

Hook it into the API base class:

```ruby
module API
  class Base < Sinatra::Base
    configure do
      set :rate_limiter, RateLimiter.new(
        $redis,
        limit:  1000,
        window: 3600  # 1 hour
      )
    end

    before do
      content_type :json
      parse_json_body
      authenticate_request! unless public_route?
      enforce_rate_limit! if @current_user
    end

    helpers do
      def enforce_rate_limit!
        result = settings.rate_limiter.check!("user:#{current_user.id}")

        headers 'X-RateLimit-Limit'     => settings.rate_limiter.limit.to_s
        headers 'X-RateLimit-Remaining' => result[:remaining].to_s
        headers 'X-RateLimit-Reset'     => (Time.now.to_i + result[:reset_in]).to_s
      rescue RateLimitExceeded => e
        headers 'X-RateLimit-Limit' => e.limit.to_s
        headers 'X-RateLimit-Reset' => (Time.now.to_i + e.reset_in).to_s
        halt 429, { error: { code: 'rate_limit_exceeded', message: 'Too many requests', reset_in: e.reset_in } }.to_json
      end
    end
  end
end
```

The `X-RateLimit-*` headers let clients know where they stand without having to hit the limit first - which is a nice thing to do for the front-end developers & API consumers working with your platform.

---

## Consuming External APIs

At some point your application will need to talk to the outside world - payment processors, email services, video platforms, analytics tools. Ruby has excellent HTTP client libraries for this kind of work.

### Faraday

Faraday is my preferred choice - it's middleware-based, well-maintained & has solid error handling. I've used it across many projects without issues:

```ruby
# Gemfile
gem 'faraday'
gem 'faraday-retry'
```

I build a connection object once and reuse it:

```ruby
# lib/http_client.rb
class HttpClient
  def self.build(base_url, token: nil, timeout: 10)
    Faraday.new(url: base_url) do |f|
      f.request  :json
      f.response :json, content_type: /\bjson$/
      f.response :raise_error
      f.request  :retry, max: 3, interval: 0.5, backoff_factor: 2
      f.options.timeout      = timeout
      f.options.open_timeout = 5

      f.headers['Authorization'] = "Bearer #{token}" if token
      f.headers['User-Agent']    = 'CourseMarketplace/1.0'
    end
  end
end
```

### Integrating with a Payment Webhook

The course marketplace uses Stripe. When a student completes a checkout, Stripe sends a webhook to the server confirming the payment. Here's how I'd handle that securely:

```ruby
# api/webhooks/stripe.rb
module API
  module Webhooks
    class Stripe < Sinatra::Base
      # Stripe webhooks don't use our API token auth
      # They're verified using a webhook signature instead

      post '/stripe' do
        payload   = request.body.read
        sig_header = request.env['HTTP_STRIPE_SIGNATURE']
        secret    = ENV.fetch('STRIPE_WEBHOOK_SECRET')

        begin
          event = ::Stripe::Webhook.construct_event(payload, sig_header, secret)
        rescue ::Stripe::SignatureVerificationError
          halt 400, { error: 'Invalid signature' }.to_json
        rescue JSON::ParserError
          halt 400, { error: 'Invalid payload' }.to_json
        end

        handle_stripe_event(event)

        status 200
        { received: true }.to_json
      end

      private

      def handle_stripe_event(event)
        case event['type']
        when 'checkout.session.completed'
          handle_checkout_completed(event['data']['object'])
        when 'customer.subscription.deleted'
          handle_subscription_cancelled(event['data']['object'])
        when 'invoice.payment_failed'
          handle_payment_failed(event['data']['object'])
        end
      end

      def handle_checkout_completed(session)
        enrollment_id = session.dig('metadata', 'enrollment_id')
        return unless enrollment_id

        enrollment = Enrollment.find_by(id: enrollment_id)
        return unless enrollment

        enrollment.update!(
          paid:       true,
          paid_at:    Time.now,
          stripe_session_id: session['id']
        )

        EnrollmentMailer.welcome(enrollment).deliver_now
      end

      def handle_subscription_cancelled(subscription)
        user = User.find_by(stripe_customer_id: subscription['customer'])
        return unless user

        user.update!(subscription_status: 'cancelled')
        SubscriptionMailer.cancelled(user).deliver_now
      end

      def handle_payment_failed(invoice)
        user = User.find_by(stripe_customer_id: invoice['customer'])
        return unless user

        SubscriptionMailer.payment_failed(user, invoice).deliver_now
      end
    end
  end
end
```

Mount it separately in `config.ru` so it bypasses the API authentication middleware:

```ruby
# config.ru
map '/webhooks' do
  run API::Webhooks::Stripe
end
```

### Calling an External API

Here's a practical example - fetching video metadata from a hosting service when an instructor uploads a video:

```ruby
# lib/video_service.rb
class VideoService
  BASE_URL = 'https://api.vimeo.com'

  def initialize
    @client = HttpClient.build(BASE_URL, token: ENV.fetch('VIMEO_ACCESS_TOKEN'))
  end

  def video_details(video_id)
    response = @client.get("/videos/#{video_id}", {
      fields: 'uri,name,description,duration,pictures,embed'
    })

    {
      id:          video_id,
      title:       response.body['name'],
      description: response.body['description'],
      duration:    response.body['duration'],
      thumbnail:   response.body.dig('pictures', 'sizes', -1, 'link'),
      embed_html:  response.body.dig('embed', 'html')
    }
  rescue Faraday::ResourceNotFound
    nil
  rescue Faraday::Error => e
    logger.error("VideoService error: #{e.message}")
    nil
  end

  def upload_url(size:, name:)
    response = @client.post('/me/videos', {
      upload: { approach: 'tus', size: size },
      name:   name
    })

    response.body.dig('upload', 'upload_link')
  end
end
```

And using it from a route:

```ruby
post '/instructor/courses/:id/lessons' do
  @course  = current_user.courses.find(params[:id])
  @lesson  = @course.lessons.build(lesson_params)

  if params[:vimeo_id]
    video_svc = VideoService.new
    meta      = video_svc.video_details(params[:vimeo_id])

    if meta
      @lesson.video_url       = "https://vimeo.com/#{params[:vimeo_id]}"
      @lesson.video_thumbnail = meta[:thumbnail]
      @lesson.duration_seconds = meta[:duration]
    end
  end

  if @lesson.save
    redirect "/instructor/courses/#{@course.slug}/curriculum"
  else
    erb :'instructor/new_lesson'
  end
end
```

---

## GraphQL with Sinatra

REST is great for straightforward CRUD APIs. GraphQL shines when clients need to fetch complex, nested data in a single request & you want to avoid over-fetching. A mobile app that needs a course title, the first three lessons & the instructor name doesn't want to make three separate REST calls - and your server doesn't want to be making them either.

### Setting Up graphql-ruby

```ruby
# Gemfile
gem 'graphql'
```

```bash
bundle install
```

For a plain Sinatra app, I set things up by hand (`graphiql-rails` is Rails-only; we'll wire up a lightweight GraphiQL HTML page directly instead):

```ruby
# lib/graphql/schema.rb
require 'graphql'
require_relative 'types/query_type'

module CourseMarket
  class Schema < GraphQL::Schema
    query Types::QueryType

    max_depth     10
    max_complexity 200
  end
end
```

### Defining Types

```ruby
# lib/graphql/types/course_type.rb
module Types
  class CourseType < GraphQL::Schema::Object
    description 'A course on the marketplace'

    field :id,                 ID,      null: false
    field :title,              String,  null: false
    field :description,        String,  null: true
    field :price,              Float,   null: false
    field :published,          Boolean, null: false
    field :enrollments_count,  Integer, null: false
    field :created_at,         GraphQL::Types::ISO8601DateTime, null: false

    field :instructor, Types::UserType,    null: false
    field :lessons,    [Types::LessonType], null: false

    def instructor
      # Simple lookup - swap in a batch-loader gem (e.g. `batch-loader`) if N+1
      # queries become a problem in production
      User.find(object.instructor_id)
    end

    def lessons
      object.lessons.ordered
    end
  end
end
```

```ruby
# lib/graphql/types/lesson_type.rb
module Types
  class LessonType < GraphQL::Schema::Object
    description 'A lesson within a course'

    field :id,          ID,      null: false
    field :title,       String,  null: false
    field :description, String,  null: true
    field :position,    Integer, null: false
    field :free,        Boolean, null: false
    field :duration,    Integer, null: true, description: 'Duration in seconds'
  end
end
```

```ruby
# lib/graphql/types/query_type.rb
module Types
  class QueryType < GraphQL::Schema::Object
    description 'The root query type'

    field :courses, [Types::CourseType], null: false do
      argument :category, String, required: false
      argument :limit,    Integer, required: false, default_value: 20
    end

    field :course, Types::CourseType, null: true do
      argument :id, ID, required: true
    end

    def courses(category: nil, limit: 20)
      scope = Course.published.limit([limit, 100].min)
      scope = scope.where(category: category) if category
      scope
    end

    def course(id:)
      Course.find_by(id: id)
    end
  end
end
```

### The GraphQL Endpoint

A single POST endpoint handles all GraphQL requests - which is one of the things I like about GraphQL. Everything goes through one place:

```ruby
# api/graphql_endpoint.rb
require_relative '../lib/graphql/schema'

module API
  class GraphQLEndpoint < Sinatra::Base
    before do
      content_type :json

      token        = request.env['HTTP_AUTHORIZATION']&.split(' ', 2)&.last
      @current_user = User.find_by(api_token: token)
    end

    post '/graphql' do
      body_data = JSON.parse(request.body.read, symbolize_names: true)

      query          = body_data[:query]
      variables      = body_data[:variables] || {}
      operation_name = body_data[:operationName]

      context = { current_user: @current_user }

      result = CourseMarket::Schema.execute(
        query,
        variables:      variables,
        context:        context,
        operation_name: operation_name
      )

      result.to_json
    rescue JSON::ParserError => e
      halt 400, { errors: [{ message: 'Invalid JSON' }] }.to_json
    end

    # GraphiQL in development
    if development?
      get '/graphiql' do
        content_type :html
        erb :graphiql, layout: false
      end
    end
  end
end
```

Mount it alongside the REST API:

```ruby
# config.ru
map '/api/graphql' do
  run API::GraphQLEndpoint
end
```

A client query looks like this - and this is where GraphQL really earns its place:

```graphql
query GetCourseWithLessons($id: ID!) {
  course(id: $id) {
    id
    title
    price
    instructor {
      name
      bio
    }
    lessons {
      id
      title
      position
      free
      duration
    }
  }
}
```

The client gets exactly what it asked for in a single request. GraphQL isn't always the right choice - for simple APIs, REST is honestly less complex to maintain - but for data-rich frontends & mobile apps it's well worth the setup cost.

---

## Testing and Documenting Your APIs

### Testing with Rack::Test

`Rack::Test` is built into Sinatra's test helpers and lets you drive your API without spinning up a real server. I pair it with RSpec and you get fast, reliable API tests:

```ruby
# Gemfile (test group)
gem 'rspec'
gem 'rack-test'
gem 'factory_bot'
gem 'database_cleaner-active_record'
```

```ruby
# spec/spec_helper.rb
require 'rack/test'
require_relative '../api/v1/app'

RSpec.configure do |config|
  config.include Rack::Test::Methods

  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning { example.run }
  end
end
```

```ruby
# spec/api/v1/courses_spec.rb
require 'spec_helper'
require 'factory_bot'

RSpec.describe 'Courses API' do
  def app
    API::V1::Courses
  end

  let(:user)  { FactoryBot.create(:user, :instructor) }
  let(:token) { user.api_token }

  def auth_headers
    { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
  end

  describe 'GET /' do
    before do
      FactoryBot.create_list(:course, 5, :published)
      FactoryBot.create_list(:course, 3, :draft)
    end

    it 'returns published courses only' do
      get '/', {}, auth_headers

      expect(last_response.status).to eq(200)

      body = JSON.parse(last_response.body, symbolize_names: true)
      expect(body[:data].length).to eq(5)
    end

    it 'paginates results' do
      get '/?per_page=2&page=1', {}, auth_headers

      body = JSON.parse(last_response.body, symbolize_names: true)
      expect(body[:data].length).to eq(2)
      expect(body[:meta][:total]).to eq(5)
    end

    it 'filters by category' do
      FactoryBot.create(:course, :published, category: 'design')

      get '/?category=design', {}, auth_headers

      body = JSON.parse(last_response.body, symbolize_names: true)
      expect(body[:data].length).to eq(1)
    end
  end

  describe 'POST /' do
    it 'creates a course for an instructor' do
      payload = { title: 'Ruby Mastery', description: 'Learn Ruby', price: 49.99 }

      post '/', payload.to_json, auth_headers.merge('CONTENT_TYPE' => 'application/json')

      expect(last_response.status).to eq(201)

      body = JSON.parse(last_response.body, symbolize_names: true)
      expect(body[:title]).to eq('Ruby Mastery')
    end

    it 'rejects creation for non-instructors' do
      non_instructor = FactoryBot.create(:user)
      headers = { 'HTTP_AUTHORIZATION' => "Bearer #{non_instructor.api_token}" }

      post '/', { title: 'Test' }.to_json, headers.merge('CONTENT_TYPE' => 'application/json')

      expect(last_response.status).to eq(403)
    end

    it 'returns 422 for missing required fields' do
      post '/', { title: 'No description or price' }.to_json, auth_headers.merge('CONTENT_TYPE' => 'application/json')

      expect(last_response.status).to eq(400)

      body = JSON.parse(last_response.body, symbolize_names: true)
      expect(body.dig(:error, :code)).to eq('missing_parameters')
    end
  end

  describe 'DELETE /:id' do
    it 'removes the course' do
      course = FactoryBot.create(:course, instructor: user)

      delete "/#{course.id}", {}, auth_headers

      expect(last_response.status).to eq(204)
      expect(Course.find_by(id: course.id)).to be_nil
    end

    it 'returns 404 for courses owned by others' do
      other_course = FactoryBot.create(:course)

      delete "/#{other_course.id}", {}, auth_headers

      expect(last_response.status).to eq(404)
    end
  end
end
```

A few things I've found worth noting about API testing in Rack::Test - always check `last_response.status` and don't assume a 200. Parse the response body and check structure, not just content. Test error cases as thoroughly as happy paths - that's honestly where most bugs live. And use `FactoryBot` to build test data cleanly, cleaning up between tests with `DatabaseCleaner`.

### Testing Webhooks

Stripe webhook tests need a valid signature - generate one using Stripe's test helper:

```ruby
RSpec.describe 'Stripe Webhook' do
  def app
    API::Webhooks::Stripe
  end

  def webhook_headers(payload)
    timestamp = Time.now.to_i
    secret    = ENV.fetch('STRIPE_WEBHOOK_SECRET', 'whsec_test_secret')
    signature = Stripe::Webhook::Signature.compute_signature(timestamp, payload, secret)

    {
      'CONTENT_TYPE'          => 'application/json',
      'HTTP_STRIPE_SIGNATURE' => "t=#{timestamp},v1=#{signature}"
    }
  end

  it 'activates enrollment on checkout.session.completed' do
    enrollment = FactoryBot.create(:enrollment, paid: false)

    payload = {
      type: 'checkout.session.completed',
      data: {
        object: {
          id:       'cs_test_123',
          metadata: { enrollment_id: enrollment.id.to_s }
        }
      }
    }.to_json

    post '/stripe', payload, webhook_headers(payload)

    expect(last_response.status).to eq(200)
    expect(enrollment.reload.paid).to be(true)
  end
end
```

### Documenting with OpenAPI

Good documentation is part of a good API - I'd argue it's non-negotiable if anyone else is going to use it. OpenAPI (formerly Swagger) is the standard for describing REST APIs in a machine-readable format. Tools like Swagger UI and Redoc turn an OpenAPI spec into interactive documentation your users can actually test against.

I generally write the spec by hand in YAML:

```yaml
# docs/openapi.yaml
openapi: "3.1.0"
info:
  title: Course Marketplace API
  version: "1.0.0"
  description: |
    The Course Marketplace API allows you to browse courses,
    manage enrollments, and build integrations.

servers:
  - url: https://api.coursemarket.example.com/api/v1
    description: Production

security:
  - BearerAuth: []

components:
  securitySchemes:
    BearerAuth:
      type: http
      scheme: bearer

  schemas:
    Course:
      type: object
      properties:
        id:
          type: integer
        title:
          type: string
        description:
          type: string
        price:
          type: number
          format: float
        enrollments_count:
          type: integer

    Error:
      type: object
      properties:
        error:
          type: object
          properties:
            code:
              type: string
            message:
              type: string
            details:
              type: array
              items:
                type: string

paths:
  /courses:
    get:
      summary: List published courses
      parameters:
        - name: page
          in: query
          schema: { type: integer, default: 1 }
        - name: per_page
          in: query
          schema: { type: integer, default: 20, maximum: 100 }
        - name: category
          in: query
          schema: { type: string }
        - name: sort
          in: query
          schema:
            type: string
            enum: [popular, newest, price_asc]
      responses:
        "200":
          description: A list of courses
          content:
            application/json:
              schema:
                type: object
                properties:
                  data:
                    type: array
                    items:
                      $ref: '#/components/schemas/Course'
                  meta:
                    type: object
```

Then serve the documentation from the app in development:

```ruby
get '/docs' do
  redirect 'https://redocly.github.io/redoc/?url=' + URI.encode_www_form_component(
    "#{request.base_url}/openapi.yaml"
  )
end

get '/openapi.yaml' do
  content_type 'application/yaml'
  File.read(File.join(settings.root, 'docs', 'openapi.yaml'))
end
```

If you'd rather generate documentation from your code, look at the `rswag` gem or write a simple DSL on top of your Sinatra routes that emits an OpenAPI spec. Hand-written specs tend to age better because they stay decoupled from implementation details, but auto-generated specs guarantee accuracy - it's a tradeoff and either approach works.

---

APIs are where Sinatra genuinely excels - the lack of ceremony means you can focus on your resource model, your authentication strategy & your error handling without fighting a framework. The patterns in this chapter (a base class, versioned mounts, consistent error format, rate limiting) give you a solid foundation to build on without locking you into any particular structure.

In the next chapter I'll look at testing & deployment, making sure everything we've built runs reliably in production.
