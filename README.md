<div align="center">
   <img src="/img/logo.svg?raw=true" width=600 style="background-color:white;">
</div>

# Backend Engineering Take-Home Assignment: Dynamic Pricing Proxy
## Core Requirements

1. Review the pricing model's API and its constraints. The model's docker image and documentation are hosted on dockerhub:  [tripladev/rate-api](https://hub.docker.com/r/tripladev/rate-api).

2. Ensure rate validity. A rate fetched from the pricing model is considered valid for 5 minutes. Your service must ensure that any rate it provides for a given set of parameters (`period`, `hotel`, `room`) is no older than this 5-minute window.

3. Honor throughput requirements. Your solution must be able to handle at least 10,000 requests per day from our users while using a single API token.


## Solution Explanation

Please refer to the [doc](/doc) folder

### Quick Start Guide

I am mostly using the same stack and infrastructure as provided by the boilerplate, so the same commands can be used as-is to build, run, and test the application.

```bash

# --- 1. Build & Run The Main Application ---
# Build and run the Docker compose
docker compose up -d --build

# --- 2. Test The Endpoint ---
# Send a sample request to your running service
curl 'http://localhost:3000/api/v1/pricing?period=Summer&hotel=FloatingPointResort&room=SingletonRoom'

# --- 3. Run Tests ---
# Run the full test suite
docker compose exec interview-dev ./bin/rails test

# Run a specific test file
docker compose exec interview-dev ./bin/rails test test/controllers/pricing_controller_test.rb

# Run a specific test by name
docker compose exec interview-dev ./bin/rails test test/controllers/pricing_controller_test.rb -n test_should_get_pricing_with_all_parameters
```


Good luck, and we look forward to seeing what you build\!
