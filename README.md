# Rocking Sinatra

A free book teaching advanced, production-oriented Sinatra development by building a Udemy-like course marketplace.

## About This Book

This is not a beginner's book - it dives straight into advanced topics for building real-world production software with Sinatra. The first two chapters cover essential concepts, then we build a fully functional course marketplace.

I highly recommend reading the [Sinatra documentation](https://sinatrarb.com) and having a solid understanding of Ruby before starting.

Recommended Ruby resources:

1. [Eloquent Ruby, Second Edition](https://pragprog.com/titles/eruby2/eloquent-ruby-second-edition/) by Russ Olsen
2. [Practical Object-Oriented Design in Ruby](https://www.poodr.com/) by Sandi Metz
3. [The Odin Project](https://www.theodinproject.com/) (free, comprehensive full-stack curriculum)

## What We're Building

A fully functional Udemy-type clone where users can buy and publish short video courses, featuring user management, authentication, REST & GraphQL APIs, real-time WebSockets, database-backed content, and production deployment.

## Running the Example Code

Each example in the `examples/` directory is self-contained with its own `Gemfile`:

```bash
cd examples/ch01-modular
bundle install
bundle exec rackup
# Open http://localhost:9292
```

For chapters that use PostgreSQL or Redis, use the included Docker environment:

```bash
docker compose up
```

See [Running Examples](book/running-examples.md) for full details.

## Contents

#### [Chapter 1 - Important Concepts](book/ch1-important-concepts.md)

1. [Classic vs Modular Style Applications](book/ch1-important-concepts.md#classic-vs-modular-style-applications)
2. [Useful Tools](book/ch1-important-concepts.md#useful-tools) - Sinatra Contrib, Helpers, Logging, Code Analyzers
3. [A Brief Introduction to Rack](book/ch1-important-concepts.md#a-brief-introduction-to-rack)
4. [Software Architecture Patterns](book/ch1-important-concepts.md#software-architecture-patterns)

#### [Chapter 2 - Working with Routes & Conditions](book/ch2-routes-and-conditions.md)

1. [Named Parameters](book/ch2-routes-and-conditions.md#named-parameters)
2. [Wildcard Routing](book/ch2-routes-and-conditions.md#wildcard-routing)
3. [Routing with Regular Expressions](book/ch2-routes-and-conditions.md#routing-with-regular-expressions)
4. [Using Query String Parameters](book/ch2-routes-and-conditions.md#using-query-string-parameters)
5. [Routing Conditions](book/ch2-routes-and-conditions.md#routing-conditions)

#### [Chapter 3 - Templates, Partials, Layouts & Emails](book/ch3-templates-layouts.md)

1. [Configuration](book/ch3-templates-layouts.md#configuration)
2. [Types of Template Engines](book/ch3-templates-layouts.md#types-of-template-engines)
3. [Namespacing Templates](book/ch3-templates-layouts.md#namespacing-templates)
4. [Layouts](book/ch3-templates-layouts.md#layouts)
5. [Embedding Partials](book/ch3-templates-layouts.md#embedding-partials)
6. [Effectively Dealing with Mailers](book/ch3-templates-layouts.md#effectively-dealing-with-mailers)

#### [Chapter 4 - Rendering CSS, Images & JavaScript Assets](book/ch4-assets.md)

1. [Rake-based Asset Bundling](book/ch4-assets.md#rake-based-asset-bundling)
2. [Sprockets](book/ch4-assets.md#sprockets)
3. [Serving Directly with Rack::Static](book/ch4-assets.md#serving-directly-with-rackstatic)
4. [Effective Caching](book/ch4-assets.md#effective-caching)
5. [Serving Assets from Nginx](book/ch4-assets.md#serving-assets-from-nginx)

#### [Chapter 5 - WebSockets, Ajax & CORS](book/ch5-websockets-ajax-cors.md)

1. [Understanding WebSockets](book/ch5-websockets-ajax-cors.md#understanding-websockets)
2. [Basic WebSocket Setup with Sinatra](book/ch5-websockets-ajax-cors.md#basic-websocket-setup-with-sinatra)
3. [Realtime Chat Application](book/ch5-websockets-ajax-cors.md#realtime-chat-application)
4. [Embeddable JavaScript Applications with CORS](book/ch5-websockets-ajax-cors.md#embeddable-javascript-applications-with-cors)
5. [Realtime Exception Tracking System](book/ch5-websockets-ajax-cors.md#realtime-exception-tracking-system)

#### [Chapter 6 - Structuring Your Applications](book/ch6-structuring-applications.md)

1. [MVC & Directory Structure](book/ch6-structuring-applications.md#mvc--directory-structure)
2. [Helpers](book/ch6-structuring-applications.md#helpers)
3. [Settings / Configuration](book/ch6-structuring-applications.md#settings--configuration)
4. [Application Boot Process](book/ch6-structuring-applications.md#application-boot-process)
5. [Creating Custom Helpers](book/ch6-structuring-applications.md#creating-custom-helpers)
6. [Creating Custom Extensions](book/ch6-structuring-applications.md#creating-custom-extensions)

#### [Chapter 7 - Working with Databases](book/ch7-working-with-databases.md)

1. [ActiveRecord with PostgreSQL](book/ch7-working-with-databases.md#activerecord-with-postgresql)
2. [Redis](book/ch7-working-with-databases.md#redis)
3. [Workshop: Modeling Our Course Marketplace](book/ch7-working-with-databases.md#workshop-modeling-our-course-marketplace)

#### [Chapter 8 - Securing Your Application](book/ch8-securing-your-application.md)

1. [User Authentication](book/ch8-securing-your-application.md#user-authentication)
2. [Rack Protection Module](book/ch8-securing-your-application.md#rack-protection-module)
3. [API Authentication](book/ch8-securing-your-application.md#api-authentication)
4. [OAuth Authentication](book/ch8-securing-your-application.md#oauth-authentication)
5. [Input Validation](book/ch8-securing-your-application.md#input-validation)
6. [SSL/HTTPS in Production](book/ch8-securing-your-application.md#sslhttps-in-production)

#### [Chapter 9 - All About APIs](book/ch9-apis.md)

1. [Basic REST API Principles](book/ch9-apis.md#basic-rest-api-principles)
2. [Creating a JSON API Service](book/ch9-apis.md#creating-a-json-api-service)
3. [API Authentication](book/ch9-apis.md#api-authentication)
4. [Consuming External APIs](book/ch9-apis.md#consuming-external-apis)
5. [GraphQL with Sinatra](book/ch9-apis.md#graphql-with-sinatra)
6. [Testing & Documenting Your APIs](book/ch9-apis.md#testing--documenting-your-apis)

#### [Chapter 10 - Testing & Deployment](book/ch10-testing-and-deployment.md)

1. [Testing with Rack::Test](book/ch10-testing-and-deployment.md#testing-with-racktest)
2. [Testing with RSpec](book/ch10-testing-and-deployment.md#testing-with-rspec)
3. [Testing with Minitest](book/ch10-testing-and-deployment.md#testing-with-minitest)
4. [Containerized Deployment with Docker](book/ch10-testing-and-deployment.md#containerized-deployment-with-docker)
5. [Deploying with Puma behind Nginx](book/ch10-testing-and-deployment.md#deploying-with-puma-behind-nginx)
6. [Production Checklist](book/ch10-testing-and-deployment.md#production-checklist)

## Contributing

If you want to help by contributing to the content of this book, please submit a [pull request](https://github.com/sn/rocking-sinatra/pulls).

## Author

Sean Nieuwoudt - [sean@underwulf.com](mailto:sean@underwulf.com)

## License

[MIT](LICENSE)
