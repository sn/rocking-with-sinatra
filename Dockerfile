FROM ruby:3.3-slim

RUN apt-get update && apt-get install -y \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile* ./
RUN bundle install

COPY . .

EXPOSE 9292

CMD ["bundle", "exec", "rackup", "--host", "0.0.0.0"]
