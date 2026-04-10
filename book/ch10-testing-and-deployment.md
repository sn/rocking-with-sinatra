# Chapter 10 - Testing & Deployment

I've found that the gap between "it works on my machine" and "it works in production" is where most Sinatra projects quietly fall apart. Testing & deployment aren't the exciting parts of building a course marketplace, but I can guarantee you that skipping them will cost you more time than investing in them upfront ever would.

I generally approach this in two phases - get the test suite to a point where I trust it, then deploy with enough infrastructure around the app that it can actually survive real traffic. For testing I'll walk through Rack::Test, RSpec & Minitest so you can pick whatever fits how you already think. For deployment we'll cover Docker, Puma behind Nginx, and the handful of production settings that seem minor but really aren't.

## Testing with Rack::Test

`Rack::Test` is a separate gem - add `gem 'rack-test'` to your test group and you're good to go. It lets you fire HTTP requests against your app in-process without binding to a port, which keeps tests fast & the setup dead simple. For smaller apps I honestly reach for this first and only graduate to something heavier when I actually need it.

### Setting Up Rack::Test

Your `Gemfile` needs very little:

```ruby
# Gemfile
source 'https://rubygems.org'

gem 'sinatra', '~> 4.0'
gem 'sinatra-contrib'
gem 'puma'
gem 'rackup'
gem 'activerecord'
gem 'pg'
gem 'dotenv'

group :test do
  gem 'rack-test'
  gem 'minitest', '~> 5.0'
end
```

Then create a `test/test_helper.rb` to boot your app:

```ruby
# test/test_helper.rb
ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require_relative '../app'

module AppTestHelpers
  include Rack::Test::Methods

  def app
    App
  end
end
```

Every test file that includes that module gets the full Rack::Test DSL - `get`, `post`, `put`, `delete`, `patch`, `last_response`, `last_request` - the works.

### Testing GET Routes

Here's what testing a course listing page looks like. Nothing surprising:

```ruby
# test/courses_test.rb
require_relative 'test_helper'

class CoursesTest < Minitest::Test
  include AppTestHelpers

  def test_homepage_returns_200
    get '/'
    assert_equal 200, last_response.status
  end

  def test_course_listing_renders
    get '/courses'
    assert last_response.ok?
    assert_match 'Browse Courses', last_response.body
  end

  def test_course_listing_filters_by_category
    get '/courses', category: 'ruby'
    assert last_response.ok?
    # The query param should be reflected in the response
    assert_match 'ruby', last_response.body
  end

  def test_unknown_course_returns_404
    get '/courses/this-course-does-not-exist'
    assert_equal 404, last_response.status
  end
end
```

`last_response` is a `Rack::MockResponse` object - you get `status`, `body`, `headers`, and the convenience predicates `ok?`, `redirect?`, `not_found?`, `server_error?`.

### Testing POST Routes

Form submissions & API writes need a bit more care. I always want to verify both the happy path and what happens when data is missing or invalid - the sad paths are usually where the bugs actually live:

```ruby
# test/enrollments_test.rb
require_relative 'test_helper'

class EnrollmentsTest < Minitest::Test
  include AppTestHelpers

  def setup
    # Use a real test database or a transaction that gets rolled back
    @course = Course.create!(
      title: 'Introduction to Ruby',
      slug: 'intro-ruby',
      price: 0,
      published: true
    )
  end

  def teardown
    Course.delete_all
    Enrollment.delete_all
  end

  def test_guest_cannot_enroll
    post "/courses/#{@course.slug}/enroll"
    assert_equal 302, last_response.status
    assert_match '/login', last_response.headers['Location']
  end

  def test_authenticated_user_can_enroll
    # Simulate a logged in session by passing it as the env hash
    post "/courses/#{@course.slug}/enroll", {}, 'rack.session' => { user_id: 1 }
    assert last_response.redirect?
    assert_match "/learn/#{@course.slug}", last_response.headers['Location']
  end

  def test_enrollment_with_missing_course_returns_404
    post '/courses/non-existent-slug/enroll'
    assert_equal 404, last_response.status
  end
end
```

### Testing with Sessions and Cookies

Sessions in Sinatra are backed by a cookie, and Rack::Test gives you `rack_mock_session` & `set_cookie` to manipulate them. I've found the cleanest approach is a helper that signs you in before a test - that way the login logic lives in one place:

```ruby
# test/test_helper.rb (extended)
module AppTestHelpers
  include Rack::Test::Methods

  def app
    App
  end

  def login_as(user)
    # POST to your actual login route
    post '/login', email: user.email, password: 'test_password'
    follow_redirect! if last_response.redirect?
  end

  def logout
    delete '/logout'
  end
end
```

Then in your tests you get a nice readable flow:

```ruby
def test_instructor_dashboard_requires_login
  get '/instructor/dashboard'
  assert last_response.redirect?
  assert_match '/login', last_response.headers['Location']
end

def test_instructor_sees_their_courses
  user = User.create!(email: 'instructor@example.com', role: 'instructor')
  login_as(user)

  get '/instructor/dashboard'
  assert last_response.ok?
end
```

If you need to set session values directly without going through a login route at all, you can pass them as the third argument to the request method:

```ruby
def with_session(hash)
  env_hash = { 'rack.session' => hash }
  yield env_hash
end

def test_something_with_session
  get '/protected', {}, 'rack.session' => { user_id: 42, role: 'admin' }
  assert last_response.ok?
end
```

### Testing JSON API Responses

For the JSON API parts of the marketplace, I parse the response body and assert on the actual data structure rather than matching strings in the body. It's more precise and doesn't break when you change your HTML templates:

```ruby
# test/api_test.rb
require_relative 'test_helper'
require 'json'

class APITest < Minitest::Test
  include AppTestHelpers

  def setup
    @api_key = ApiKey.create!(user_id: 1).token
    @headers  = { 'HTTP_API_KEY' => @api_key, 'CONTENT_TYPE' => 'application/json' }
  end

  def test_courses_endpoint_returns_json
    get '/api/v1/courses', {}, @headers
    assert last_response.ok?
    assert_equal 'application/json', last_response.content_type.split(';').first

    payload = JSON.parse(last_response.body)
    assert_kind_of Array, payload
  end

  def test_single_course_endpoint
    course = Course.create!(title: 'Ruby Metaprogramming', slug: 'ruby-meta', published: true)

    get "/api/v1/courses/#{course.id}", {}, @headers
    assert last_response.ok?

    payload = JSON.parse(last_response.body)
    assert_equal 'Ruby Metaprogramming', payload['title']
    assert_equal 'ruby-meta', payload['slug']
  end

  def test_missing_api_key_returns_401
    get '/api/v1/courses'
    assert_equal 401, last_response.status

    payload = JSON.parse(last_response.body)
    assert_equal 'Invalid API key', payload['error']
  end

  def test_create_course_via_api
    payload = { title: 'New Course', description: 'Learn stuff', price: 29 }.to_json

    post '/api/v1/courses', payload, @headers
    assert_equal 201, last_response.status

    result = JSON.parse(last_response.body)
    assert result['id']
    assert_equal 'New Course', result['title']
  end

  def test_create_course_with_invalid_data_returns_422
    payload = { title: '' }.to_json

    post '/api/v1/courses', payload, @headers
    assert_equal 422, last_response.status

    result = JSON.parse(last_response.body)
    assert result['errors']
  end
end
```

The third argument to `get`/`post` is the Rack environment hash - that's where headers live. The `HTTP_` prefix is Rack's convention for request headers, which catches everyone out the first time.

## Testing with RSpec

If you prefer RSpec, the setup is a bit more involved but I've found the resulting test files read almost like a spec document - which is kind of the point. RSpec's `describe`/`context`/`it` structure lends itself well to capturing expected behaviour in a way that's easy to scan.

### Gemfile Setup

```ruby
# Gemfile
group :test do
  gem 'rspec', '~> 3.13'
  gem 'rack-test'
  gem 'factory_bot', '~> 6.0'
  gem 'faker'
  gem 'database_cleaner-active_record'
end
```

Run `bundle exec rspec --init` to generate `.rspec` & `spec/spec_helper.rb`, then fill in the spec helper:

### spec_helper.rb Configuration

```ruby
# spec/spec_helper.rb
ENV['RACK_ENV'] = 'test'

require 'rspec'
require 'rack/test'
require 'factory_bot'
require 'database_cleaner/active_record'
require_relative '../app'

RSpec.configure do |config|
  config.include Rack::Test::Methods
  config.include FactoryBot::Syntax::Methods
  # Defines `app` as an instance method on every example group so Rack::Test
  # picks it up correctly - a bare `def app` inside configure only defines it
  # on the RSpec::Core::Configuration object, not on examples.
  config.include(Module.new { def app = App })

  # Database cleanup strategy
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
    FactoryBot.find_definitions
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning { example.run }
  end

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
```

Add a `.rspec` file at your project root - the defaults are pretty noisy and `--format documentation` is much easier to read:

```
# .rspec
--require spec_helper
--format documentation
--color
```

### Defining Factories

Put your FactoryBot definitions in `spec/factories/`. I like to use traits for the different states a record can be in - it keeps the factory definitions lean & makes test setup very readable:

```ruby
# spec/factories/users.rb
FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password_digest  { BCrypt::Password.create('password') }
    role             { 'student' }

    trait :instructor do
      role { 'instructor' }
    end

    trait :admin do
      role { 'admin' }
    end
  end
end

# spec/factories/courses.rb
FactoryBot.define do
  factory :course do
    association :user, factory: [:user, :instructor]
    sequence(:title) { |n| "Course #{n}" }
    sequence(:slug)  { |n| "course-#{n}" }
    description      { Faker::Lorem.paragraph }
    price            { 0 }
    published        { false }

    trait :published do
      published { true }
    end

    trait :paid do
      price { 49 }
    end
  end
end
```

### Writing Request Specs

```ruby
# spec/requests/courses_spec.rb
require 'spec_helper'

RSpec.describe 'Courses', type: :request do
  describe 'GET /courses' do
    context 'when there are published courses' do
      before do
        create_list(:course, 3, :published)
        create(:course) # unpublished, should not appear
      end

      it 'returns 200' do
        get '/courses'
        expect(last_response.status).to eq(200)
      end

      it 'shows only published courses' do
        get '/courses'
        # We have 3 published courses - the body should reflect that
        expect(last_response.body).to include('Course ')
      end
    end

    context 'when filtering by category' do
      let!(:ruby_courses) { create_list(:course, 2, :published, category: 'ruby') }
      let!(:js_courses)   { create_list(:course, 2, :published, category: 'javascript') }

      it 'returns only courses in the requested category' do
        get '/courses', category: 'ruby'
        expect(last_response.status).to eq(200)
      end
    end
  end

  describe 'GET /courses/:slug' do
    let(:course) { create(:course, :published) }

    it 'returns the course detail page' do
      get "/courses/#{course.slug}"
      expect(last_response.status).to eq(200)
    end

    it 'returns 404 for an unknown slug' do
      get '/courses/does-not-exist'
      expect(last_response.status).to eq(404)
    end
  end

  describe 'POST /courses/:slug/enroll' do
    let(:course) { create(:course, :published) }

    context 'when not logged in' do
      it 'redirects to login' do
        post "/courses/#{course.slug}/enroll"
        expect(last_response.status).to eq(302)
        expect(last_response.headers['Location']).to include('/login')
      end
    end

    context 'when logged in as a student' do
      let(:student) { create(:user) }

      it 'creates an enrollment and redirects to the course player' do
        expect {
          post "/courses/#{course.slug}/enroll", {}, 'rack.session' => { user_id: student.id }
        }.to change(Enrollment, :count).by(1)

        expect(last_response.status).to eq(302)
        expect(last_response.headers['Location']).to include("/learn/#{course.slug}")
      end
    end
  end
end
```

### Testing Model Validations

You don't need to go through HTTP to test ActiveRecord validations. Testing the model directly is faster & more focused:

```ruby
# spec/models/course_spec.rb
require 'spec_helper'

RSpec.describe Course, type: :model do
  subject(:course) { build(:course) }

  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(course).to be_valid
    end

    it 'requires a title' do
      course.title = ''
      expect(course).not_to be_valid
      expect(course.errors[:title]).to include("can't be blank")
    end

    it 'requires a unique slug' do
      create(:course, slug: 'my-course')
      course.slug = 'my-course'
      expect(course).not_to be_valid
      expect(course.errors[:slug]).to include('has already been taken')
    end

    it 'requires price to be zero or positive' do
      course.price = -5
      expect(course).not_to be_valid
    end
  end

  describe '#published?' do
    it 'returns false for a draft course' do
      expect(build(:course).published?).to be(false)
    end

    it 'returns true for a published course' do
      expect(build(:course, :published).published?).to be(true)
    end
  end

  describe '#free?' do
    it 'returns true when price is zero' do
      expect(build(:course, price: 0).free?).to be(true)
    end

    it 'returns false when price is positive' do
      expect(build(:course, :paid).free?).to be(false)
    end
  end
end
```

Run your specs with the usual RSpec commands:

```bash
bundle exec rspec
bundle exec rspec spec/requests/  # just request specs
bundle exec rspec spec/models/    # just model specs
```

## Testing with Minitest

If you'd rather avoid RSpec's DSL entirely and keep things close to plain Ruby, Minitest is a great fit. It boots faster, the test code is just Ruby classes, and there's genuinely no magic. Some developers find that refreshing (doesn't every project have enough magic already?).

### Minitest Setup

```ruby
# Gemfile (test group)
group :test do
  gem 'minitest', '~> 5.0'
  gem 'minitest-reporters'  # prettier output
  gem 'rack-test'
  gem 'database_cleaner-active_record'
end
```

Here's a minimal test helper that does the database cleanup setup for you:

```ruby
# test/test_helper.rb
ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'minitest/reporters'
require 'rack/test'
require 'database_cleaner/active_record'
require_relative '../app'

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

DatabaseCleaner.strategy = :transaction

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    App
  end

  def setup
    DatabaseCleaner.start
  end

  def teardown
    DatabaseCleaner.clean
  end
end
```

Inherit from `AppTest` instead of `Minitest::Test` in your test files and you get the database cleanup & Rack::Test for free - no repeated boilerplate per file:

```ruby
# test/courses_test.rb
require_relative 'test_helper'

class CoursesTest < AppTest
  def test_published_courses_appear_in_listing
    Course.create!(title: 'Ruby Basics', slug: 'ruby-basics', published: true, price: 0)
    Course.create!(title: 'Draft Course', slug: 'draft', published: false, price: 0)

    get '/courses'

    assert last_response.ok?
    assert_match 'Ruby Basics', last_response.body
    refute_match 'Draft Course', last_response.body
  end

  def test_course_show_returns_404_for_missing_slug
    get '/courses/this-slug-does-not-exist'
    assert_equal 404, last_response.status
  end
end

class CourseModelTest < Minitest::Test
  def setup
    DatabaseCleaner.start
  end

  def teardown
    DatabaseCleaner.clean
  end

  def test_course_requires_title
    course = Course.new(slug: 'test', price: 0)
    refute course.valid?
    assert_includes course.errors[:title], "can't be blank"
  end

  def test_course_slug_must_be_unique
    Course.create!(title: 'First', slug: 'my-slug', price: 0)
    second = Course.new(title: 'Second', slug: 'my-slug', price: 0)
    refute second.valid?
  end
end
```

Run your tests with a Rake task - shell glob expansion for `**/*` is inconsistent across platforms and shells, so a Rake task is the reliable way to pick up all test files:

```ruby
# Rakefile
require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = false
end

task default: :test
```

```bash
bundle exec rake test          # run all tests
bundle exec rake test TEST=test/courses_test.rb  # run one file
```

The main practical difference between Minitest & RSpec really is just style. RSpec's `describe`/`context`/`it` reads like documentation. Minitest reads like code. Both work well with Sinatra - I'd honestly just pick whichever your team already knows rather than introducing a learning curve for the sake of it.

## Containerized Deployment with Docker

Docker solves the "works on my machine" problem by packaging your app & all its dependencies into a portable image. I've found it's the right default for anything cloud-hosted in 2024+ - the consistency between development, CI & production alone is worth the small upfront effort.

### Dockerfile for a Sinatra App

Here's a Dockerfile using a multi-stage build to keep the production image lean. The build stage does all the compilation work and the runtime stage only carries what the app actually needs to run:

```dockerfile
# Dockerfile
# --- Build stage ---
FROM ruby:3.3-slim AS builder

RUN apt-get update && apt-get install -y \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3

# --- Runtime stage ---
FROM ruby:3.3-slim AS runtime

RUN apt-get update && apt-get install -y \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user to run the app
RUN groupadd --gid 1000 app && \
    useradd --uid 1000 --gid app --shell /bin/bash --create-home app

WORKDIR /app

# Copy the installed gems from the build stage
COPY --from=builder /usr/local/bundle /usr/local/bundle

# Copy application code
COPY --chown=app:app . .

USER app

EXPOSE 9292

ENV RACK_ENV=production

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
```

The multi-stage build means the final image only carries the runtime libraries (`libpq5`) - not the build tools (`build-essential`, `libpq-dev`). That typically shaves 200-400MB off the image size, which adds up when you're pulling images on every deploy.

### docker-compose.yml for Development

For local development you want the full stack - app, PostgreSQL & Redis - all starting with a single command. Here's a `docker-compose.yml` that does exactly that:

```yaml
# docker-compose.yml
services:
  app:
    build: .
    ports:
      - "9292:9292"
    volumes:
      - .:/app
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      RACK_ENV: development
      DATABASE_URL: postgres://postgres:postgres@postgres:5432/rocking_sinatra
      REDIS_URL: redis://redis:6379
      SESSION_SECRET: dev_session_secret_change_in_production
    command: bundle exec rackup --host 0.0.0.0 --port 9292

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  postgres:
    image: postgres:16-alpine
    ports:
      - "5432:5432"
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: rocking_sinatra
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  pgdata:
```

The `healthcheck` conditions on `depends_on` are easy to overlook but they matter - without them your app container can start before PostgreSQL is actually ready to accept connections, and you'll spend ten minutes wondering why migrations are failing. With them, Docker waits.

Start the whole stack:

```bash
docker compose up --build
docker compose run app bundle exec rake db:migrate
docker compose run app bundle exec rake db:seed
```

Tear it down when you're done:

```bash
docker compose down          # stops containers, keeps data
docker compose down -v       # stops containers, deletes volumes (wipes database)
```

### Environment Variable Management

Never bake secrets into your image - please don't do that unless the world is ending. Use environment variables for everything that changes between environments, and commit a `.env.example` so the next developer knows what's expected:

```bash
# .env.example  (commit this)
RACK_ENV=development
DATABASE_URL=postgres://postgres:postgres@localhost:5432/rocking_sinatra
REDIS_URL=redis://localhost:6379
SESSION_SECRET=change_me
STRIPE_SECRET_KEY=sk_test_...
STRIPE_PUBLISHABLE_KEY=pk_test_...
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_BUCKET=
SENTRY_DSN=

# .env  (never commit this - add to .gitignore)
```

Load them in your app with `dotenv` in development & test, and rely on real environment variables in production:

```ruby
# config/environment.rb
require 'dotenv/load' if %w[development test].include?(ENV.fetch('RACK_ENV', 'development'))

module Config
  DATABASE_URL    = ENV.fetch('DATABASE_URL')
  REDIS_URL       = ENV.fetch('REDIS_URL', 'redis://localhost:6379')
  SESSION_SECRET  = ENV.fetch('SESSION_SECRET')
  STRIPE_SECRET   = ENV.fetch('STRIPE_SECRET_KEY', nil)
end
```

`ENV.fetch` raises a `KeyError` if the variable is missing, which is exactly what you want. A hard crash at startup beats a subtle nil error three layers deep at runtime every single time.

## Deploying with Puma behind Nginx

Docker is great for development & cloud container platforms like Fly.io, Render, Railway or ECS. But if you're deploying to a plain Linux server - a VPS you control - the most battle-tested stack I've used is Puma handling Ruby requests behind Nginx as a reverse proxy. It's not glamorous but it works.

### Puma Configuration

Create `config/puma.rb` - I tend to keep this fairly minimal and let environment variables handle the tuning per server:

```ruby
# config/puma.rb
workers ENV.fetch('WEB_CONCURRENCY', 2).to_i
threads_count = ENV.fetch('PUMA_MAX_THREADS', 5).to_i
threads threads_count, threads_count

preload_app!

port        ENV.fetch('PORT', 9292)
environment ENV.fetch('RACK_ENV', 'production')

# Store PID for process management
pidfile    ENV.fetch('PIDFILE', 'tmp/pids/puma.pid')

# Bind to a Unix socket for Nginx to proxy to
# Comment out `port` above and use this in production:
# bind 'unix:///tmp/puma.sock'

on_worker_boot do
  # Re-establish database connections after fork
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
end

on_worker_shutdown do
  ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord)
end

before_fork do
  # Close connections before forking
  ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord)
end
```

`preload_app!` loads your application code in the master process before forking workers. It's faster because workers inherit the loaded code via copy-on-write, but it requires that `on_worker_boot` reconnect block - file descriptors including database connections can't safely be shared across a fork.

The worker count rule of thumb I follow: set `WEB_CONCURRENCY` to the number of CPU cores on your server. For IO-bound apps (most web apps hitting a database), threads fill in the gaps between the forked workers.

### Nginx Reverse Proxy Config

Nginx sits in front of Puma & handles SSL termination, static file serving & connection management. Here's the config I'd use for the course marketplace:

```nginx
# /etc/nginx/sites-available/coursemarketplace
upstream puma_app {
    server unix:///tmp/puma.sock fail_timeout=0;
}

server {
    listen 80;
    server_name yourapp.com www.yourapp.com;

    # Redirect all HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl;
    http2 on;
    server_name yourapp.com www.yourapp.com;

    ssl_certificate     /etc/letsencrypt/live/yourapp.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourapp.com/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers   HIGH:!aNULL:!MD5;

    root /var/www/coursemarketplace/current/public;

    # Serve static files directly from Nginx (much faster than Puma)
    try_files $uri/index.html $uri @puma;

    location @puma {
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header Host              $http_host;

        proxy_redirect off;
        proxy_pass http://puma_app;

        # Timeouts - adjust for your app's slowest requests
        proxy_read_timeout   60s;
        proxy_connect_timeout 60s;
        proxy_send_timeout   60s;
    }

    # Deny access to dotfiles
    location ~ /\. {
        deny all;
    }

    # Cache static assets aggressively
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    client_max_body_size 50m;

    access_log /var/log/nginx/coursemarketplace_access.log;
    error_log  /var/log/nginx/coursemarketplace_error.log;
}
```

Enable the site and reload Nginx to pick it up:

```bash
sudo ln -s /etc/nginx/sites-available/coursemarketplace /etc/nginx/sites-enabled/
sudo nginx -t          # test the config
sudo systemctl reload nginx
```

### Systemd Service File for Puma

Rather than managing Puma in a screen session (please don't do that in production), use systemd so it starts automatically on boot & gets restarted if it crashes:

```ini
# /etc/systemd/system/coursemarketplace.service
[Unit]
Description=Course Marketplace Puma Server
After=network.target postgresql.service redis.service

[Service]
Type=simple
User=deploy
Group=deploy
WorkingDirectory=/var/www/coursemarketplace/current

# Load environment from a file (never store secrets in the unit file)
EnvironmentFile=/var/www/coursemarketplace/shared/.env

ExecStart=/usr/local/bin/bundle exec puma -C config/puma.rb
ExecReload=/bin/kill -USR1 $MAINPID
ExecStop=/bin/kill -SIGTERM $MAINPID

Restart=always
RestartSec=5

# Give Puma time to finish in-flight requests on shutdown
TimeoutStopSec=60
KillMode=mixed

StandardOutput=append:/var/log/coursemarketplace/puma.log
StandardError=append:/var/log/coursemarketplace/puma_error.log

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable coursemarketplace
sudo systemctl start coursemarketplace
sudo systemctl status coursemarketplace
```

To deploy a new version without taking the app offline, Puma supports phased restarts:

```bash
# Phased restart - workers are replaced one at a time
sudo systemctl kill --kill-who=main -s USR1 coursemarketplace

# Hot restart (re-executes the Puma binary, useful after gem updates)
sudo systemctl kill --kill-who=main -s USR2 coursemarketplace
```

`USR1` tells Puma to finish current requests on each worker then restart it with new code. Traffic keeps flowing while the workers cycle through. `USR2` does a full binary restart - use that one when you've updated gems.

## Production Checklist

Before you flip the switch, run through this. It's short but I can guarantee every item on it has bitten someone in production - often at the worst possible time.

### Force HTTPS

Nginx handles the HTTP to HTTPS redirect, but I also add it at the application level as a belt-and-suspenders measure. If someone points a second domain at your server that bypasses the Nginx config, you're still covered:

The `rack-ssl` gem is deprecated and shouldn't be used in new projects - the Nginx redirect in the config above handles it cleanly at the proxy layer. If you want belt-and-suspenders coverage at the app level too, a `before` filter is all you need:

```ruby
before do
  if settings.production? && !request.secure?
    redirect request.url.sub('http://', 'https://'), 301
  end
end
```

### Set RACK_ENV=production

This matters more than it sounds. When `RACK_ENV` is `production`, Sinatra disables static file serving (Nginx handles it), disables the exception backtrace page (you really don't want users seeing that), and enables response caching for templates. Make sure it's set in your systemd `EnvironmentFile` and in your Docker image's `ENV` directive - both.

### Database Connection Pooling

With multiple Puma workers & threads, you need enough database connections - each thread needs one. I've been caught out by this before and the failure mode is unpleasant (requests silently queue waiting for a connection). Configure your pool explicitly:

```ruby
# config/database.rb
ActiveRecord::Base.establish_connection(
  adapter:  'postgresql',
  url:      ENV.fetch('DATABASE_URL'),
  pool:     ENV.fetch('DB_POOL', 5).to_i,
  timeout:  5000,
  checkout_timeout: 5
)
```

A safe formula: `pool = WEB_CONCURRENCY * PUMA_MAX_THREADS`. With 2 workers and 5 threads each, you need a pool of at least 10. And don't forget to check that PostgreSQL's `max_connections` is large enough to accommodate your pool across all app servers - it defaults to 100 on most setups, which disappears quickly once you have a few services connecting.

### Logging Configuration

In production you want structured logs, not the default Sinatra development output. JSON logs are a small investment that pays off enormously the first time you need to search through thousands of lines in a log aggregator:

```ruby
# config/logging.rb
require 'logger'

configure :production do
  # Log to stdout for Docker/systemd to capture
  logger = Logger.new($stdout)
  logger.level = Logger::INFO
  logger.formatter = proc do |severity, time, _progname, msg|
    {
      time: time.utc.iso8601,
      severity: severity,
      message: msg
    }.to_json + "\n"
  end

  set :logger, logger
  use Rack::CommonLogger, logger
end
```

Datadog, Papertrail, CloudWatch - they all work best when each log line is a JSON object you can filter & query on field values.

### Error Monitoring

You need to know when things break in production before your users email you about it - and they will email you about it. I'd drop in Sentry or Honeybadger on day one. Both have Rack middleware that captures unhandled exceptions & sends them to a dashboard with a full stack trace:

```ruby
# Gemfile
gem 'sentry-ruby'

# config.ru
require 'sentry-ruby'

Sentry.init do |config|
  config.dsn = ENV.fetch('SENTRY_DSN')
  config.traces_sample_rate = 0.1  # Sample 10% of transactions for performance
end

use Sentry::Rack::CaptureExceptions
run App
```

Honeybadger is even simpler if you want fewer moving parts:

```ruby
# Gemfile
gem 'honeybadger'

# config.ru
require 'honeybadger'
# Honeybadger reads HONEYBADGER_API_KEY from the environment automatically
run App
```

Either way, set the DSN or API key as an environment variable and commit nothing else.

### Health Check Endpoint

Load balancers, uptime monitors & Kubernetes all need a URL to hit to determine whether your app is healthy. It's a five-minute addition that makes everything else easier to automate:

```ruby
# app.rb
get '/health' do
  content_type :json

  checks = {
    database: database_healthy?,
    redis: redis_healthy?,
    version: ENV.fetch('APP_VERSION', 'unknown')
  }

  status_code = checks.values.all? { |v| v == true || v.is_a?(String) } ? 200 : 503

  status status_code
  checks.to_json
end

private

def database_healthy?
  ActiveRecord::Base.connection.execute('SELECT 1')
  true
rescue StandardError
  false
end

def redis_healthy?
  $redis.ping == 'PONG'
  true
rescue StandardError
  false
end
```

A 200 means everything is up. A 503 tells the load balancer to stop sending traffic to this instance. Keep it fast - it'll be hit every 10-30 seconds by whatever is monitoring you, so you don't want it doing anything expensive.

---

That's the full testing & deployment picture for a production Sinatra app. I'd start with Rack::Test because the setup is minimal and it's often all you need - graduate to RSpec when your suite grows large enough that the `describe`/`context` organisation starts paying for itself. For deployment, Docker is my default for anything cloud-hosted; the Puma/Nginx/systemd stack is still the right call when you control a VPS and want direct, simple control over what's running.

The checklist isn't exhaustive - there's always more to tune - but HTTPS, `RACK_ENV`, connection pooling, structured logging, error monitoring & a health endpoint will get you to a solid baseline. Everything else can layer on top of that.
