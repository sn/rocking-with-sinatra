# Chapter 7 - Working with Databases

Sooner or later every app needs to remember something - and that's where your database choices matter more than most developers realise early on. For our course marketplace we need to store users, courses, lessons, enrollments, payments - the whole lot. In this chapter I'll walk you through the two tools I reach for most in production Sinatra apps: PostgreSQL via ActiveRecord for your primary relational data, and Redis for caching, sessions & real-time features.

I'm keeping the scope tight on purpose. There's no shortage of blog posts walking you through ten different ORMs and three different NoSQL options. What I've found actually helps when shipping a production Sinatra app is a deep understanding of a small number of tools - not a shallow tour of everything. PostgreSQL & Redis will take you much further than you'd think.

## ActiveRecord with PostgreSQL

If you've used Rails, ActiveRecord is already familiar. What surprises most people is how cleanly it runs without Rails. You get migrations, associations, validations, scopes, callbacks - all of it - with just a Gemfile entry and a bit of setup.

### Configuration

Here's what I use for the `Gemfile`:

```ruby
# Gemfile
source 'https://rubygems.org'

ruby '3.3.0'

gem 'sinatra', '~> 4.0'
gem 'sinatra-activerecord', '~> 2.0'
gem 'pg', '~> 1.5'
gem 'puma', '~> 6.0'

group :development, :test do
  gem 'rake'
  gem 'dotenv'
end
```

The `sinatra-activerecord` gem is a thin bridge that wires ActiveRecord into Sinatra and gives you the Rake tasks you'd normally get from Rails. It auto-registers the extension when you `require 'sinatra/activerecord'`, so you don't need an explicit `register Sinatra::ActiveRecordExtension` call. Add it to your `config.ru`:

```ruby
# config.ru
require 'dotenv/load'
require_relative 'app'

run App
```

Your main application file sets up the connection:

```ruby
# app.rb
require 'sinatra/base'
require 'sinatra/activerecord'

class App < Sinatra::Base
  set :database_file, 'config/database.yml'

  # ... routes
end
```

Your `database.yml` should look familiar if you've worked with Rails:

```yaml
# config/database.yml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch('DB_POOL', 5) %>
  host: <%= ENV.fetch('DB_HOST', 'localhost') %>
  username: <%= ENV.fetch('DB_USERNAME', 'postgres') %>
  password: <%= ENV.fetch('DB_PASSWORD', '') %>

development:
  <<: *default
  database: coursemarketplace_development

test:
  <<: *default
  database: coursemarketplace_test

production:
  <<: *default
  database: coursemarketplace_production
  pool: <%= ENV.fetch('DB_POOL', 10) %>
```

And a `.env` file for local development:

```bash
# .env
DB_HOST=localhost
DB_USERNAME=postgres
DB_PASSWORD=yourpassword
DB_POOL=5
```

Finally, your `Rakefile` gives you the database management tasks:

```ruby
# Rakefile
require 'dotenv/load'
require 'sinatra/activerecord/rake'
require_relative 'app'
```

With that in place you have access to the same Rake tasks you know from Rails:

```bash
bundle exec rake db:create
bundle exec rake db:migrate
bundle exec rake db:rollback
bundle exec rake db:schema:dump
bundle exec rake db:seed
```

Run `bundle exec rake -T` to see the full list.

### Migrations

Migrations are how you evolve your database schema over time without losing data or manually running SQL on your production server. Let's build the tables for our course marketplace.

Create a migration:

```bash
bundle exec rake db:create_migration NAME=create_users
```

This generates a file in `db/migrate/` with a timestamp prefix. Let's define our users table:

```ruby
# db/migrate/20240101000001_create_users.rb
class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.string  :email,           null: false
      t.string  :password_digest, null: false
      t.string  :full_name,       null: false
      t.string  :role,            null: false, default: 'student'
      t.string  :avatar_url
      t.string  :bio
      t.boolean :confirmed,       null: false, default: false
      t.string  :confirmation_token
      t.string  :reset_token
      t.datetime :reset_token_expires_at
      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :confirmation_token, unique: true
    add_index :users, :reset_token, unique: true
  end
end
```

Now courses:

```ruby
# db/migrate/20240101000002_create_courses.rb
class CreateCourses < ActiveRecord::Migration[7.1]
  def change
    create_table :courses do |t|
      t.references :user, null: false, foreign_key: true   # the instructor
      t.string  :title,       null: false
      t.string  :slug,        null: false
      t.text    :description
      t.text    :short_description
      t.string  :status,      null: false, default: 'draft'
      t.decimal :price,       precision: 8, scale: 2, null: false, default: 0
      t.string  :thumbnail_url
      t.string  :preview_video_url
      t.string  :level,       default: 'beginner'
      t.string  :language,    default: 'en'
      t.integer :enrollments_count, null: false, default: 0
      t.tsvector :search_vector
      t.timestamps
    end

    add_index :courses, :slug,          unique: true
    add_index :courses, :status
    add_index :courses, :user_id
    add_index :courses, :search_vector, using: :gin
  end
end
```

Lessons belong to courses:

```ruby
# db/migrate/20240101000003_create_lessons.rb
class CreateLessons < ActiveRecord::Migration[7.1]
  def change
    create_table :lessons do |t|
      t.references :course,  null: false, foreign_key: true
      t.string  :title,      null: false
      t.text    :description
      t.string  :video_url
      t.integer :position,   null: false, default: 0
      t.integer :duration_seconds, default: 0
      t.boolean :free_preview, null: false, default: false
      t.boolean :published,  null: false, default: false
      t.timestamps
    end

    add_index :lessons, [:course_id, :position]
  end
end
```

And enrollments to track who is taking what:

```ruby
# db/migrate/20240101000004_create_enrollments.rb
class CreateEnrollments < ActiveRecord::Migration[7.1]
  def change
    create_table :enrollments do |t|
      t.references :user,   null: false, foreign_key: true
      t.references :course, null: false, foreign_key: true
      t.string  :status,  null: false, default: 'active'
      t.decimal :amount_paid, precision: 8, scale: 2, null: false, default: 0
      t.datetime :completed_at
      t.timestamps
    end

    add_index :enrollments, [:user_id, :course_id], unique: true
    add_index :enrollments, :status
  end
end
```

Run all of them in one go:

```bash
bundle exec rake db:migrate
```

If you make a mistake, roll back the last migration and fix it:

```bash
bundle exec rake db:rollback
```

One habit worth forming early - never edit a migration that has already been run on any shared environment (staging, production). Write a new migration instead that makes the corrective change. This keeps the migration history consistent for everyone on the team.

### Queries & Scopes

Once your models exist, ActiveRecord queries work exactly as you'd expect. The key difference from Rails is that you're just calling class methods directly - no magic, no framework wiring needed.

Here are the basics using our `Course` model:

```ruby
# Find by primary key - raises ActiveRecord::RecordNotFound if missing
course = Course.find(1)

# Find by attribute - returns nil if missing
course = Course.find_by(slug: 'intro-to-ruby')

# Raise an error if not found
course = Course.find_by!(slug: 'intro-to-ruby')

# Basic where clause
published_courses = Course.where(status: 'published')

# Chaining conditions
recent_published = Course.where(status: 'published')
                         .where('created_at > ?', 30.days.ago)
                         .order(created_at: :desc)

# Limit and offset
page_one = Course.where(status: 'published').limit(20).offset(0)
```

Named scopes keep your models clean & your query logic out of your routes. Define them on the model:

```ruby
# models/course.rb
class Course < ActiveRecord::Base
  belongs_to :user  # the instructor
  has_many :lessons, -> { order(:position) }
  has_many :enrollments

  scope :published,  -> { where(status: 'published') }
  scope :draft,      -> { where(status: 'draft') }
  scope :free,       -> { where(price: 0) }
  scope :paid,       -> { where('price > 0') }
  scope :recent,     -> { order(created_at: :desc) }
  scope :popular,    -> { order(enrollments_count: :desc) }
  scope :by_level,   ->(level) { where(level: level) }
  scope :by_instructor, ->(user) { where(user: user) }
end
```

Scopes are chainable, which is where they really shine:

```ruby
# In your route handler
get '/courses' do
  @courses = Course.published.recent.limit(24)
  @courses = @courses.free if params[:free] == '1'
  @courses = @courses.by_level(params[:level]) if params[:level]
  erb :courses
end
```

For queries that might hit the database repeatedly with the same result, eager loading prevents the N+1 problem - and this bites you hard on course listings where you're displaying instructor information alongside each course:

```ruby
# Bad - fires one query for courses, then one per course for the instructor
courses = Course.published.limit(20)
courses.each { |c| puts c.user.full_name }  # N+1 queries

# Good - loads everything in two queries
courses = Course.published.includes(:user).limit(20)
courses.each { |c| puts c.user.full_name }  # 2 queries total
```

Go further and include nested associations when you need them:

```ruby
# Load courses with instructor and all lessons in 3 queries
courses = Course.published
                .includes(:user, :lessons)
                .where('lessons.published = ?', true)
                .references(:lessons)
                .limit(20)
```

Use `joins` when you need to filter based on an association but don't need the associated data loaded:

```ruby
# Courses that have at least one published lesson
courses = Course.joins(:lessons)
                .where(lessons: { published: true })
                .distinct
                .published
```

### Associations

Well-defined associations are what make ActiveRecord powerful. Here's the full set of models for our marketplace:

```ruby
# models/user.rb
class User < ActiveRecord::Base
  has_secure_password

  has_many :courses,     foreign_key: :user_id  # courses taught
  has_many :enrollments, dependent: :destroy
  has_many :enrolled_courses, through: :enrollments, source: :course

  scope :instructors, -> { where(role: 'instructor') }
  scope :students,    -> { where(role: 'student') }

  def instructor?
    role == 'instructor'
  end

  def student?
    role == 'student'
  end

  def enrolled_in?(course)
    enrollments.exists?(course: course, status: 'active')
  end
end
```

```ruby
# models/course.rb
class Course < ActiveRecord::Base
  belongs_to :user  # the instructor
  has_many :lessons,     -> { order(:position) }, dependent: :destroy
  has_many :enrollments, dependent: :destroy
  has_many :students, through: :enrollments, source: :user

  scope :published,  -> { where(status: 'published') }
  scope :draft,      -> { where(status: 'draft') }
  scope :popular,    -> { order(enrollments_count: :desc) }
  scope :recent,     -> { order(created_at: :desc) }

  def instructor
    user
  end

  def published?
    status == 'published'
  end

  def free?
    price.zero?
  end
end
```

```ruby
# models/lesson.rb
class Lesson < ActiveRecord::Base
  belongs_to :course

  scope :published, -> { where(published: true) }
  scope :free,      -> { where(free_preview: true) }

  def duration_formatted
    total = duration_seconds || 0
    minutes = total / 60
    seconds = total % 60
    format('%02d:%02d', minutes, seconds)
  end
end
```

```ruby
# models/enrollment.rb
class Enrollment < ActiveRecord::Base
  belongs_to :user
  belongs_to :course

  scope :active,    -> { where(status: 'active') }
  scope :completed, -> { where(status: 'completed') }

  after_create :increment_course_counter
  after_destroy :decrement_course_counter

  private

  def increment_course_counter
    course.increment!(:enrollments_count)
  end

  def decrement_course_counter
    course.decrement!(:enrollments_count)
  end
end
```

The `has_many :through` association is particularly useful here. You can query across the join table naturally:

```ruby
user = User.find(1)

# All courses a student is enrolled in
user.enrolled_courses.published

# All students enrolled in a specific course
course = Course.find(1)
course.students.where(confirmed: true)

# Check enrollment in a single query
user.enrolled_in?(course)  # uses enrollments.exists?
```

### Validations

Validations go on the model, not in the route handler - this keeps your routes thin & your business rules centralized. I've seen projects where every route duplicates the same checks and it's a nightmare to maintain.

```ruby
# models/user.rb
class User < ActiveRecord::Base
  has_secure_password

  VALID_ROLES = %w[student instructor admin].freeze

  validates :email,
    presence: true,
    uniqueness: { case_sensitive: false },
    format: { with: URI::MailTo::EMAIL_REGEXP }

  validates :full_name,
    presence: true,
    length: { minimum: 2, maximum: 100 }

  validates :role,
    inclusion: { in: VALID_ROLES }

  before_save { email.downcase! }
end
```

```ruby
# models/course.rb
class Course < ActiveRecord::Base
  belongs_to :user

  VALID_STATUSES = %w[draft published archived].freeze
  VALID_LEVELS   = %w[beginner intermediate advanced].freeze

  validates :title,
    presence: true,
    length: { minimum: 5, maximum: 150 }

  validates :slug,
    presence: true,
    uniqueness: true,
    format: { with: /\A[a-z0-9\-]+\z/, message: 'only lowercase letters, numbers, and hyphens' }

  validates :status,
    inclusion: { in: VALID_STATUSES }

  validates :level,
    inclusion: { in: VALID_LEVELS }

  validates :price,
    numericality: { greater_than_or_equal_to: 0 }

  validate :instructor_must_be_confirmed, on: :create

  before_validation :generate_slug, if: -> { slug.blank? && title.present? }

  private

  def generate_slug
    base = title.downcase.gsub(/[^a-z0-9\s]/, '').gsub(/\s+/, '-')
    self.slug = base
    # Handle duplicates
    counter = 1
    while Course.exists?(slug: self.slug)
      self.slug = "#{base}-#{counter}"
      counter += 1
    end
  end

  def instructor_must_be_confirmed
    return unless user
    unless user.confirmed?
      errors.add(:base, 'Instructor account must be confirmed before publishing courses')
    end
  end
end
```

In your route handlers, check `valid?` or let `save` return false and inspect `errors`:

```ruby
post '/courses' do
  @course = current_user.courses.build(
    title:       params[:title],
    description: params[:description],
    price:       params[:price],
    level:       params[:level]
  )

  if @course.save
    redirect "/instructor/courses/#{@course.slug}"
  else
    @errors = @course.errors.full_messages
    status 422
    erb :'instructor/new_course'
  end
end
```

One thing I always do - use `save!`, `create!`, and `update!` during seeding & background jobs where you want an exception rather than a silent failure. In route handlers, use the non-bang versions and check the return value.

### Full Text Search

PostgreSQL has built-in full text search that is genuinely good. For a course marketplace, I've found it's often all you need - you can skip ElasticSearch entirely until you have a compelling reason to add that operational complexity.

The approach uses `tsvector` (a pre-processed document) & `tsquery` (a search query). We already added a `search_vector` column to the courses table. Now let's keep it updated with a trigger:

```ruby
# db/migrate/20240101000005_add_search_trigger_to_courses.rb
class AddSearchTriggerToCourses < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION courses_search_vector_update() RETURNS trigger AS $$
      BEGIN
        NEW.search_vector :=
          setweight(to_tsvector('english', coalesce(NEW.title, '')), 'A') ||
          setweight(to_tsvector('english', coalesce(NEW.short_description, '')), 'B') ||
          setweight(to_tsvector('english', coalesce(NEW.description, '')), 'C');
        RETURN NEW;
      END
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER courses_search_vector_update
        BEFORE INSERT OR UPDATE OF title, short_description, description
        ON courses
        FOR EACH ROW EXECUTE FUNCTION courses_search_vector_update();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS courses_search_vector_update ON courses;
      DROP FUNCTION IF EXISTS courses_search_vector_update();
    SQL
  end
end
```

The trigger runs automatically whenever you insert or update a course. The `setweight` calls assign relevance levels - title matches rank higher than description matches.

Now add a search scope to the model:

```ruby
# models/course.rb
class Course < ActiveRecord::Base
  scope :search, ->(query) {
    return all if query.blank?
    where("search_vector @@ plainto_tsquery('english', ?)", query)
      .order(Arel.sql("ts_rank(search_vector, plainto_tsquery('english', #{connection.quote(query)})) DESC"))
  }
end
```

Using `plainto_tsquery` means the user can type plain text like "ruby on rails beginners" and PostgreSQL handles the tokenization. You don't need to sanitize or escape the query manually - the parameterized query handles that.

In your route:

```ruby
get '/courses/search' do
  @query   = params[:q].to_s.strip
  @courses = Course.published.search(@query).includes(:user).limit(30)
  erb :search_results
end
```

If you need to backfill existing records (say, after adding the trigger to an existing table), run this once:

```ruby
# Run from rake task or rails console
Course.find_each do |course|
  course.touch  # triggers the update callback
end
```

Or more efficiently with a single SQL statement:

```ruby
ActiveRecord::Base.connection.execute(<<~SQL)
  UPDATE courses SET
    search_vector =
      setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
      setweight(to_tsvector('english', coalesce(short_description, '')), 'B') ||
      setweight(to_tsvector('english', coalesce(description, '')), 'C');
SQL
```

### Pagination

Pagination is one of those things that looks trivial until you try to do it yourself and realise you need page numbers, total counts & edge case handling. I'd just use a gem.

The two main options are `kaminari` and `pagy`. Kaminari is more familiar to Rails developers & integrates nicely with ActiveRecord scopes. Pagy is faster and has less magic. I'll use pagy here.

Add it to your Gemfile:

```ruby
gem 'pagy', '~> 8.0'
```

Set it up as a helper in your app:

```ruby
# app.rb
require 'pagy'
require 'pagy/extras/array'

class App < Sinatra::Base
  helpers do
    include Pagy::Backend
    include Pagy::Frontend
  end

  # ...
end
```

Using it in a route is straightforward:

```ruby
get '/courses' do
  @pagy, @courses = pagy(
    Course.published.includes(:user).popular,
    limit: 24
  )
  erb :courses
end
```

In your view:

```erb
<!-- views/courses.erb -->
<div class="course-grid">
  <% @courses.each do |course| %>
    <%= erb :'partials/course_card', locals: { course: course } %>
  <% end %>
</div>

<nav class="pagination">
  <%== pagy_nav(@pagy) %>
</nav>
```

Pagy renders pagination controls as HTML. You can override the templates by creating your own `pagy` helper that returns whatever HTML your front-end design requires.

For API responses where you want pagination metadata in JSON:

```ruby
get '/api/v1/courses' do
  content_type :json

  pagy, courses = pagy(Course.published.popular, limit: 20)

  {
    data: courses.map { |c|
      { id: c.id, title: c.title, slug: c.slug, price: c.price }
    },
    pagination: {
      current_page:  pagy.page,
      total_pages:   pagy.pages,
      total_count:   pagy.count,
      per_page:      pagy.limit
    }
  }.to_json
end
```

### Clearing DB Connections

This is one of those things that bites production apps hard if you get it wrong - I can guarantee you'll run into it at some point if you haven't already. Puma uses a process-per-worker model. When Puma forks a new worker, the forked process inherits open database connections from the parent. Those connections are then shared between the parent & child processes, which corrupts them.

The fix is to disconnect before forking and reconnect after:

```ruby
# config/puma.rb
workers ENV.fetch('WEB_CONCURRENCY', 2)
threads_count = ENV.fetch('PUMA_MAX_THREADS', 5)
threads threads_count, threads_count

preload_app!

on_worker_boot do
  ActiveRecord::Base.establish_connection
end

on_worker_shutdown do
  ActiveRecord::Base.connection_pool.disconnect!
end
```

The `preload_app!` directive tells Puma to load your application code before forking workers - this improves memory usage through copy-on-write. The `on_worker_boot` block re-establishes the connection pool fresh in each worker.

Also tune your connection pool size to match Puma's thread count:

```yaml
# config/database.yml
production:
  <<: *default
  database: coursemarketplace_production
  pool: <%= ENV.fetch('DB_POOL', ENV.fetch('PUMA_MAX_THREADS', 5)) %>
```

Each Puma thread needs its own database connection. If your pool is smaller than the thread count, threads will block waiting for a connection to free up - which hurts response times under load.

For long-running background jobs, always return connections to the pool when you're done:

```ruby
# In a background worker
def process_job
  ActiveRecord::Base.connection_pool.with_connection do
    # do database work here
    course = Course.find(course_id)
    course.update!(status: 'published')
  end
  # connection automatically returned to pool
end
```

## Redis

Redis is an in-memory data structure store - it's fast, it's simple, and it handles a category of problems that relational databases handle awkwardly: ephemeral data, counters, queues, pub/sub messaging & fast caching.

For our course marketplace I'll use Redis for caching expensive queries, storing user sessions & sending real-time notifications.

### Setup and Configuration

Add the Redis gem to your Gemfile:

```ruby
gem 'redis', '~> 5.0'
```

Create a connection in a shared location that your app can reference:

```ruby
# config/redis.rb
require 'redis'

REDIS = Redis.new(
  url:            ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'),
  connect_timeout: 1,
  read_timeout:    1,
  write_timeout:   1
)
```

Require it in your app:

```ruby
# app.rb
require 'sinatra/base'
require 'sinatra/activerecord'
require_relative 'config/redis'

class App < Sinatra::Base
  # ...
end
```

Setting explicit timeouts is important in production. Without them, a Redis outage can cause your web workers to hang indefinitely waiting for a response. One second is generous - most Redis operations complete in under a millisecond.

For multiple Redis databases (Redis supports 16 by default), use different database numbers for different concerns:

```ruby
# config/redis.rb
REDIS_CACHE   = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
REDIS_SESSIONS = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'))
REDIS_PUBSUB  = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/2'))
```

If you're using Redis Cloud or similar managed services, your `REDIS_URL` will include authentication: `redis://:password@host:port/0`. The Redis gem handles this automatically from the URL.

### Using Redis for Caching

The most common use of Redis in a web app is caching - storing the result of an expensive operation so you don't have to compute it again on the next request.

Here's a simple cache helper I drop into most projects:

```ruby
# helpers/cache_helper.rb
module CacheHelper
  def cache(key, ttl: 300)
    cached = REDIS_CACHE.get(key)

    if cached
      JSON.parse(cached, symbolize_names: true)
    else
      result = yield
      REDIS_CACHE.set(key, result.to_json, ex: ttl)
      result
    end
  end

  def invalidate_cache(key)
    REDIS_CACHE.del(key)
  end

  def invalidate_pattern(pattern)
    REDIS_CACHE.scan_each(match: pattern) do |key|
      REDIS_CACHE.del(key)
    end
  end
end
```

Register it in your app:

```ruby
class App < Sinatra::Base
  helpers CacheHelper
  # ...
end
```

Now use it in routes where database queries are expensive or results change infrequently:

```ruby
get '/courses' do
  page = (params[:page] || 1).to_i
  cache_key = "courses:published:page:#{page}"

  @courses = cache(cache_key, ttl: 600) do
    pagy, courses = pagy(Course.published.includes(:user).popular)
    courses
  end

  erb :courses
end
```

For course detail pages, cache aggressively but bust the cache when the course is updated:

```ruby
# models/course.rb
class Course < ActiveRecord::Base
  after_save  :bust_cache
  after_destroy :bust_cache

  private

  def bust_cache
    REDIS_CACHE.del("course:#{slug}")
    REDIS_CACHE.del("course:#{id}")
    invalidate_pattern("courses:*")  # clear listing pages too
  end
end
```

```ruby
# In the route
get '/courses/:slug' do
  cache_key = "course:#{params[:slug]}"

  @course = cache(cache_key, ttl: 3600) do
    Course.published.includes(:user, :lessons).find_by!(slug: params[:slug])
  end

  erb :course_detail
end
```

Fragment caching is when you cache a portion of a rendered page rather than a whole query result - useful when parts of a page are expensive to render:

```ruby
# In your route or view helper
def cached_course_card(course)
  key = "fragment:course_card:#{course.id}:#{course.updated_at.to_i}"
  cached = REDIS_CACHE.get(key)
  return cached if cached

  rendered = erb(:'partials/course_card', layout: false, locals: { course: course })
  REDIS_CACHE.set(key, rendered, ex: 3600)
  rendered
end
```

Using `updated_at.to_i` in the cache key means the cache is automatically invalidated whenever the record changes. This is the Russian doll caching pattern - you don't need to manually bust fragment caches.

Counters are another area where Redis shines. Instead of hitting the database every time someone views a course, increment a Redis counter and sync it to the database periodically:

```ruby
get '/courses/:slug' do
  @course = Course.find_by!(slug: params[:slug])

  # Fast in-memory view count - no database write per request
  view_key = "course:#{@course.id}:views"
  REDIS_CACHE.incr(view_key)

  erb :course_detail
end

# Run this in a background job every few minutes
def sync_view_counts
  Course.find_each do |course|
    key = "course:#{course.id}:views"
    views = REDIS_CACHE.getdel(key).to_i
    course.increment!(:view_count, views) if views > 0
  end
end
```

### Session Storage with Redis

Storing sessions in Redis is better than the default cookie store for a few reasons - you can store more data, you can invalidate sessions server-side & you can share sessions across multiple app processes.

Add the redis-session-store gem:

```ruby
gem 'redis-session-store', '~> 0.11'
```

Configure session storage in your app:

```ruby
# app.rb
require 'redis-session-store'

class App < Sinatra::Base
  use RedisSessionStore,
    redis: { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1') },
    expire_after: 86_400 * 30,  # 30 days
    key:          '_coursemarketplace_session',
    httponly:     true,
    same_site:    :lax,
    secure:       ENV['RACK_ENV'] == 'production'

  # ...
end
```

With Redis sessions, `session[:user_id]` works exactly as before, but the data lives in Redis instead of a cookie. The cookie only holds the session ID.

One powerful benefit is the ability to force-logout users:

```ruby
# Force logout a specific user (useful for security incidents)
def invalidate_user_sessions(user_id)
  # Find all sessions for this user
  # (requires storing user_id in session and scanning for it)
  pattern = "rack.session:*"
  REDIS_SESSIONS.scan_each(match: pattern) do |key|
    session_data = REDIS_SESSIONS.get(key)
    if session_data&.include?("user_id") && session_data.include?(user_id.to_s)
      REDIS_SESSIONS.del(key)
    end
  end
end
```

For a simpler approach, store a session version on the user record and validate it on every request:

```ruby
# db/migrate/20240101000006_add_session_version_to_users.rb
class AddSessionVersionToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :session_version, :integer, null: false, default: 1
  end
end
```

```ruby
# In your before filter
before do
  if session[:user_id]
    user = User.find_by(id: session[:user_id])
    if user.nil? || user.session_version != session[:session_version]
      session.clear
      redirect '/login'
    end
    @current_user = user
  end
end

# When a user changes their password or you need to force logout
def invalidate_all_sessions(user)
  user.increment!(:session_version)
end
```

### Pub/Sub for Real-Time Features

Redis pub/sub lets you broadcast messages to any number of subscribers. For a course marketplace this is really useful for real-time notifications - "Someone just enrolled in your course", "Your video has finished processing", "A new message in your course Q&A".

The basic pattern looks like this:

```ruby
# Publisher - called from a route or background job
def notify_instructor(instructor_id, message)
  channel = "instructor:#{instructor_id}:notifications"
  payload = { message: message, timestamp: Time.now.to_i }.to_json
  REDIS_PUBSUB.publish(channel, payload)
end

# Called after a successful enrollment
post '/courses/:slug/enroll' do
  @course  = Course.find_by!(slug: params[:slug])
  enrollment = Enrollment.create!(user: current_user, course: @course)

  notify_instructor(
    @course.user_id,
    "#{current_user.full_name} enrolled in #{@course.title}"
  )

  redirect "/learn/#{@course.slug}"
end
```

The subscriber runs in a separate process or thread. Here's a simple notification worker:

```ruby
# workers/notification_worker.rb
require_relative '../config/redis'
require_relative '../app'

class NotificationWorker
  def initialize(user_id)
    @user_id  = user_id
    @listener = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/2'))
  end

  def start
    channel = "instructor:#{@user_id}:notifications"

    @listener.subscribe(channel) do |on|
      on.message do |_channel, message|
        data = JSON.parse(message)
        handle_notification(data)
      end
    end
  end

  private

  def handle_notification(data)
    # Store in database for persistence
    Notification.create!(
      user_id: @user_id,
      message: data['message'],
      occurred_at: Time.at(data['timestamp'])
    )
    # Could also send an email, push notification, etc.
  end
end
```

For serving real-time notifications to browsers, combine pub/sub with Server-Sent Events (SSE). SSE is simpler than WebSockets for one-way server-to-client pushes:

```ruby
# app.rb
get '/notifications/stream', provides: 'text/event-stream' do
  halt 401 unless current_user

  channel = "instructor:#{current_user.id}:notifications"

  stream(:keep_open) do |out|
    listener = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/2'))

    listener.subscribe(channel) do |on|
      on.message do |_ch, message|
        out << "data: #{message}\n\n"
      end
    end

    out.callback { listener.unsubscribe }
    out.errback  { listener.unsubscribe }
  end
end
```

On the client side, connecting to this stream is just a few lines of JavaScript:

```javascript
const source = new EventSource('/notifications/stream');

source.onmessage = (event) => {
  const notification = JSON.parse(event.data);
  showNotification(notification.message);
};

source.onerror = () => {
  // Reconnect automatically - EventSource handles this
  console.log('SSE connection lost, reconnecting...');
};
```

Worth noting - the streaming route above will hold a thread open for each connected client. With Puma, each open stream consumes a thread from your pool. For a small number of concurrent users this is fine. If you expect thousands of concurrent connections, I'd look at using Thin with EventMachine or a dedicated push notification service.

## Workshop: Modeling Our Course Marketplace Data

Before you write a line of code, it pays to think through your data model. Bad decisions here are painful to undo - they show up as slow queries, awkward joins & migration headaches months later.

Here's the thinking behind the choices I made in this chapter.

**Users are polymorphic by role, not by table.** There's one `users` table with a `role` column rather than separate `instructors` and `students` tables. This simplifies authentication & means a user can be both a student (enrolled in courses) and an instructor (teaching their own) without needing two accounts. The tradeoff is that you need to be careful with scopes & validations to enforce role-specific rules.

**Enrollments as a first-class model.** The join table between users & courses is called `enrollments`, not `course_students`. It carries its own data: `amount_paid`, `status`, `completed_at`. This is the right call whenever a many-to-many relationship has attributes of its own - a plain join table would lose that information.

**Counter cache on courses.** The `enrollments_count` column on the `courses` table is a denormalization, but a deliberate one. Counting enrollments for every course on a listing page is expensive. Maintaining the counter via callbacks is cheap. This is a pattern worth using whenever you display a count in a list view.

**Slug on courses, not just ID.** URLs like `/courses/intro-to-ruby-3` are better than `/courses/47` for SEO & user trust. The slug is unique, indexed & generated from the title. I handle slug uniqueness with a simple counter suffix.

**Indexes worth having.** Beyond the obvious primary keys & foreign keys, the indexes that matter most for our access patterns:

- `courses.slug` - every course page lookup goes through here
- `courses.status` - every listing filters on this
- `courses.search_vector` using GIN - full text search
- `enrollments(user_id, course_id)` unique - enforces one enrollment per user per course and makes `enrolled_in?` fast
- `lessons(course_id, position)` - course curriculum is always fetched ordered by position

**Redis for the right things.** I put sessions in Redis because it gives server-side session invalidation. I put caching in Redis because it's faster than the database & easy to expire. I do not put anything in Redis that I cannot afford to lose - Redis can be configured for persistence, but I'd assume it's ephemeral. Anything that needs to survive a Redis restart belongs in PostgreSQL.

**What I left out.** A real course marketplace would also need: a `reviews` table, a `categories` table, a `payments` table, a `video_assets` table & probably a separate `notifications` table for persistent notifications. The patterns are the same - define the associations, add the indexes your access patterns need & use Redis to avoid hitting the database for things that change infrequently.

The skeleton built here is enough to run the core of the marketplace. When you add new features, I'd ask two questions: does this data need to survive a server restart? If yes, it goes in PostgreSQL. Does this data need to be accessed faster than a database query allows, or does it have a natural expiry? If yes, it goes in Redis.

Those two questions will serve you well across every feature you build.
