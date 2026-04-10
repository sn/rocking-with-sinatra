# Chapter 4 - Rendering CSS, Images & JavaScript Assets

As with views, Sinatra gives you plenty flexibility when dealing with assets. It's up to you where and how files should be stored and accessed, there's no real pre-defined location, but there are best practices you should follow.

We'll be exploring a few approaches in this chapter and I'll explain the pros and cons of each. By the end, you'll have a solid understanding of how to handle assets in production Sinatra applications.

## Thoughts on Decoupling

The simplest route is always the best route when dealing with assets.

Assets are best separated from the rest of your application in order to help front-end developers & designers do their best work without relying on the backend. Following this simple & seemingly obvious guideline will save you and your team hundreds of hours of confusion, testing and bug fixing.

Your application's assets and markup files are closely related and can be bundled under the user experience and presentation layer. It's important to offer your customers a good experience and you can do your bit by getting the structure right from the beginning.

## A Maintainable Asset Strategy

When choosing an asset management strategy, you need to be clear about the outcome and weigh up your options. Other dependencies like CSS preprocessors and JavaScript compilers need to be taken into account.

I generally follow these three rules:

1. Assets must always be minified and concatenated in production
2. Assets may not be minified or concatenated in development
3. A clear naming convention should be used to keep assets aligned with the general association to the backend codebase

The minification of assets in production can be considered good practice as it speeds up your site delivery to the end user and allows you to effectively employ browser caching.

With our example app, we're going to start by creating good habits early on as you'll see.

## Serving Directly with Rack::Static

The simplest approach is to use Rack::Static middleware to serve your assets. This works well for small applications:

```ruby
# config.ru
require './app'

use Rack::Static,
  :urls => ["/images", "/js", "/css"],
  :root => "public"

run App
```

Or within your Sinatra app:

```ruby
class App < Sinatra::Base
  configure do
    set :public_folder, File.dirname(__FILE__) + '/public'
    set :static, true
  end
end
```

This tells Sinatra to serve files from the `public` directory for any request matching `/images/*`, `/js/*`, or `/css/*`.

### Adding Cache Headers

For better performance, add cache headers:

```ruby
use Rack::Static,
  :urls => ["/images", "/js", "/css"],
  :root => "public",
  :header_rules => [
    [:all, {'Cache-Control' => 'public, max-age=86400'}],
    [['css', 'js'], {'Cache-Control' => 'public, max-age=604800'}]
  ]
```

## Rake-based Asset Bundling

For many Sinatra apps, a simple Rake task that concatenates and minifies assets is all you need. This avoids adding a heavy pipeline dependency while still giving you production-ready assets:

```ruby
# Gemfile
gem 'terser'     # JavaScript minification
gem 'sassc'      # CSS compilation

# Rakefile
require 'terser'
require 'sassc'

namespace :assets do
  desc 'Compile and minify assets for production'
  task :compile do
    # Concatenate and minify JavaScript
    js_files = Dir['assets/js/*.js'].sort
    js_content = js_files.map { |f| File.read(f) }.join("\n")
    File.write('public/js/application.min.js', Terser.compile(js_content))

    # Compile and minify CSS
    css_files = Dir['assets/css/*.scss'].sort
    css_content = css_files.map { |f| SassC::Engine.new(File.read(f)).render }.join("\n")
    File.write('public/css/application.min.css', css_content)

    puts "Assets compiled successfully"
  end
end
```

In your views, reference the compiled files directly:

```erb
<!DOCTYPE html>
<html>
<head>
  <link rel="stylesheet" href="/css/application.min.css">
</head>
<body>
  <%= yield %>
  <script src="/js/application.min.js"></script>
</body>
</html>
```

This approach gives you:
- Concatenation of multiple files into single bundles
- Minification for production
- No runtime overhead - assets are compiled ahead of time
- Full control over the build process

## Sprockets

For a Rails-like asset pipeline, use Sprockets:

```ruby
# Gemfile
gem 'sprockets'
gem 'terser'
gem 'sassc'

# config/assets.rb
require 'sprockets'

module Assets
  def self.environment(root)
    @environment ||= Sprockets::Environment.new(root) do |env|
      env.append_path 'assets/javascripts'
      env.append_path 'assets/stylesheets'
      env.append_path 'assets/images'
      
      # Add bower components or npm packages
      env.append_path 'vendor/assets/bower_components'
      
      if ENV['RACK_ENV'] == 'production'
        env.js_compressor  = Terser.new
        env.css_compressor = SassC::Engine
      end
    end
  end
end

# app.rb
class App < Sinatra::Base
  configure do
    set :assets, Assets.environment(root)
  end
  
  get '/assets/*' do
    env['PATH_INFO'].sub!('/assets', '')
    settings.assets.call(env)
  end
end
```

Your application.js with Sprockets directives:

```javascript
//= require jquery
//= require underscore
//= require_tree ./models
//= require_tree ./views
//= require_self

$(document).ready(function() {
  App.initialize();
});
```

## Compiling Assets with Rake

For production, you'll want to precompile assets:

```ruby
# Rakefile
require './app'
require 'sprockets'

Rake::SprocketsTask.new do |t|
  t.environment = App.assets
  t.output      = "./public/assets"
  t.assets      = %w( application.js application.css )
end

namespace :assets do
  desc "Compile all the assets"
  task :precompile => :environment do
    App.assets.each_logical_path do |logical_path|
      if logical_path =~ /\.(css|js)$/
        asset = App.assets[logical_path]
        filename = File.join('./public/assets', logical_path)
        FileUtils.mkpath File.dirname(filename)
        asset.write_to filename
        puts "Compiled #{logical_path}"
      end
    end
  end
  
  desc "Remove compiled assets"
  task :clean do
    FileUtils.rm_rf('./public/assets')
  end
end
```

## Effective Caching

### HTTP Headers

Set proper cache headers for your assets:

```ruby
before '/assets/*' do
  # Set far-future expiry for fingerprinted assets
  if request.path =~ /\-[0-9a-f]{32}\./
    cache_control :public, max_age: 31536000  # 1 year
  else
    cache_control :public, max_age: 3600  # 1 hour
  end
end
```

### ETags and Last-Modified

```ruby
get '/css/:name.css' do
  file_path = File.join(settings.public_folder, 'css', "#{params[:name]}.css")
  
  if File.exist?(file_path)
    content = File.read(file_path)
    etag Digest::MD5.hexdigest(content)
    last_modified File.mtime(file_path)
    
    content_type 'text/css'
    content
  else
    halt 404
  end
end
```

### Gzip Compression

Enable gzip compression for text assets:

```ruby
# config.ru
use Rack::Deflater

run App
```

`Rack::Deflater` automatically compresses responses based on the client's `Accept-Encoding` header - it handles text, JSON, SVG and other compressible content types for you.

## Optimizing Server for Serving Assets

### Using a CDN

```ruby
helpers do
  def asset_path(path)
    if settings.production?
      "#{settings.cdn_host}#{path}"
    else
      path
    end
  end
  
  def image_tag(path, options = {})
    "<img src='#{asset_path("/images/#{path}")}' #{options_to_attributes(options)} />"
  end
end

configure :production do
  set :cdn_host, 'https://cdn.example.com'
end
```

### Asset Fingerprinting

Implement cache busting with fingerprinted filenames:

```ruby
helpers do
  def asset_path_with_fingerprint(path)
    return path unless settings.production?
    
    manifest = JSON.parse(File.read('public/assets/manifest.json'))
    fingerprinted = manifest[path] || path
    
    "#{settings.cdn_host}/assets/#{fingerprinted}"
  end
end
```

## Serving Assets from Nginx

In production, let Nginx handle static files for better performance:

```nginx
server {
    listen 80;
    server_name example.com;
    root /var/www/app/public;

    # Serve static assets directly
    location ~ ^/(images|js|css|fonts)/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        
        # Enable gzip compression
        gzip on;
        gzip_types text/css application/javascript image/svg+xml;
        gzip_vary on;
        
        # Try to serve pre-gzipped files
        gzip_static on;
    }
    
    # Fingerprinted assets
    location ~ "^/assets/.*-[0-9a-f]{32}\." {
        expires 1y;
        add_header Cache-Control "public, immutable";
        gzip_static on;
    }

    # Proxy other requests to Sinatra
    location / {
        proxy_pass http://localhost:9292;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

## Apache Configuration

If you're using Apache:

```apache
<VirtualHost *:80>
    ServerName example.com
    DocumentRoot /var/www/app/public
    
    # Enable compression
    <IfModule mod_deflate.c>
        AddOutputFilterByType DEFLATE text/html text/css application/javascript
    </IfModule>
    
    # Cache static assets
    <FilesMatch "\.(jpg|jpeg|png|gif|ico|css|js)$">
        Header set Cache-Control "max-age=31536000, public"
    </FilesMatch>
    
    # Fingerprinted assets
    <FilesMatch "-[0-9a-f]{32}\.(css|js)$">
        Header set Cache-Control "max-age=31536000, public, immutable"
    </FilesMatch>
    
    # Proxy to Sinatra app
    ProxyPreserveHost On
    ProxyPass /images !
    ProxyPass /css !
    ProxyPass /js !
    ProxyPass / http://localhost:9292/
    ProxyPassReverse / http://localhost:9292/
</VirtualHost>
```

## Real-World Example: Complete Asset Pipeline

Let's put it all together with a production-ready asset setup:

```ruby
# Gemfile
gem 'sinatra'
gem 'sprockets'
gem 'terser'
gem 'sassc'
gem 'terser'

# lib/asset_helpers.rb
module AssetHelpers
  def asset_path(source)
    return "/#{source}" unless settings.production?
    
    if digest = assets_manifest[source]
      "/assets/#{digest}"
    else
      "/#{source}"
    end
  end
  
  def javascript_include_tag(*sources)
    sources.map { |source|
      "<script src='#{asset_path("#{source}.js")}'></script>"
    }.join("\n")
  end
  
  def stylesheet_link_tag(*sources)
    sources.map { |source|
      "<link href='#{asset_path("#{source}.css")}' rel='stylesheet' />"
    }.join("\n")
  end
  
  def image_tag(source, options = {})
    "<img src='#{asset_path("images/#{source}")}' #{hash_to_attributes(options)} />"
  end
  
  private
  
  def assets_manifest
    @assets_manifest ||= begin
      if File.exist?('public/assets/manifest.json')
        JSON.parse(File.read('public/assets/manifest.json'))
      else
        {}
      end
    end
  end
  
  def hash_to_attributes(hash)
    hash.map { |k, v| "#{k}=\"#{v}\"" }.join(' ')
  end
end

# app.rb
class App < Sinatra::Base
  helpers AssetHelpers
  
  configure do
    set :assets, Sprockets::Environment.new(root)
    
    # Configure asset paths
    settings.assets.append_path 'assets/javascripts'
    settings.assets.append_path 'assets/stylesheets'
    settings.assets.append_path 'assets/images'
  end
  
  configure :development do
    # Serve assets dynamically in development
    get '/assets/*' do
      env['PATH_INFO'].sub!('/assets', '')
      settings.assets.call(env)
    end
  end
  
  configure :production do
    # Compress assets in production
    settings.assets.js_compressor  = Terser.new
    settings.assets.css_compressor = SassC::Engine
    
    # Use precompiled assets
    set :static, true
    set :public_folder, 'public'
  end
end
```

That covers the essential approaches to handling assets in Sinatra. Start simple with Rack::Static for small apps, but don't hesitate to bring in more sophisticated solutions as your application grows. The key is choosing the right tool for your specific needs and always keeping performance in mind.
