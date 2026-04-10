### Running the Examples

All example code is organized in the `examples/` directory at the root of this repository. Each example is self-contained with its own `Gemfile`.

Navigate into the example directory you want to run:

```
cd examples/ch01-modular
bundle install
bundle exec rackup
```

You should now have a local development server running. Open your browser and point it to: `http://127.0.0.1:9292`

`bundle exec rackup` runs within the context of the current project bundle, so all gems bundled with your app will be in scope.

If required for the chapter, special instructions will be provided in a `README.md` file inside each example directory.

To save space, I don't always include full code for the layouts, partials, views & assets in the book itself, but those can be referenced from the available example code.

#### Requirements

The example code uses modern Ruby (3.2+) and Sinatra 4.x. I recommend using a version manager like [rbenv](https://github.com/rbenv/rbenv) or [asdf](https://asdf-vm.com/) to install Ruby.

#### Docker Environment

For chapters that require services like PostgreSQL or Redis, a Docker Compose environment is provided in the repository root:

```
docker compose up
```

This starts:
- **Redis** on port 6379
- **PostgreSQL** on port 5432 (user: `postgres`, password: `postgres`, database: `rocking_sinatra`)

You can then run the examples locally while connecting to these services. Alternatively, run the app itself inside Docker:

```
docker compose run --rm app bash
cd examples/ch01-modular
bundle install
bundle exec rackup --host 0.0.0.0
```

#### Example Directory Structure

```
examples/
  ch01-classic/       # Classic-style Sinatra app
  ch01-modular/       # Modular-style Sinatra app
  websocket-sinatra/  # WebSocket examples
  websocket-eventmachine/  # EventMachine WebSocket examples
```

Each directory contains at minimum:
- `Gemfile` - Dependencies
- `app.rb` - Application code
- `config.ru` - Rack configuration (for modular apps)
