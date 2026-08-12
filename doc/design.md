# Requirements

1. Provide a rate API, where a given rate is valid for 5 minutes, and serve a valid (non-stale) rate for each request
    - A rate is determined based on a combination of types of four Periods, three Hotels, and three Rooms
2. Be able to handle 10000 reqs/day using a single API token, which has a limit of 1000 reqs/day

# Approach

The template already includes a boilerplate code for the rate API. So I utilized and expanded on that to create the API interface.

However the real challenge lies in fulfilling 10000 reqs/day with the token's budget of 1000 reqs/day and 5 minutes validity of each rate. Furthermore, there are 36 combinations of periods, hotels, and rooms (`4 * 3 * 3`). We can do some quick maths:

```
1 day = 1440 minutes = 288 chunks of 5 minutes
36 rate combinations * 288 = 10368 reqs/day
```

Even if we use caching with TTL of 5 minutes, we still need to serve 10368 reqs/day to serve all possible rate combinations.

Fortunately, we can take advantage of Tripla's `POST /pricing` API by passing multiple items in the `attributes` array in the request body. This allows us to fetch all 36 combinations of rates in a single API call. With caching, effectively this enables us to serve 10000 reqs/day with only 288 downstream API calls per day.

# High Level Overview
Please view [this page](/doc/pricing_service_sequence.md) for a sequence diagram outlining the overall flow of the system.

# Implementation Details

## API spec
### `GET /api/v1/pricing`

#### Request Parameters
| Name | Type | Required | Possible Values |
| --- | --- | --- | --- |
| `period` | String | Yes | `Summer`, `Autumn`, `Winter`, `Spring` |
| `hotel` |  String |Yes | `FloatingPointResort`, `GitawayHotel`, `RecursionRetreat` |
| `room` |  String |Yes | `SingletonRoom`, `BooleanTwin`, `RestfulKing` |


#### Response

| Name | Type | Required | Possible Values |
| --- | --- | --- | --- |
| `rate` | String | Yes | String representation of the rate amount, non-comma separated number |


```json
{ "rate": "25700" }
```

## Budget Gate

Before we delve into the main service logic, we can optimize upstream API call counts by having a budget gate that counts the total number of upstream calls. That way, if the API token budget is exceeded, we can fail fast and prevent the application from further reaching upstream for that period. It is implemented in redis using a cache with one key per day (`rate_cache:budget:#{formatted_date}`). Furthermore, we can emit a warning if the budget is close to exhausted.

## Fetching and Caching Rates

As mentioned before, we fetch the rate for all combinations using `POST /pricing` API. The returned response will be cached in Redis inside a single key, `rate_cache:entry`.

In order to prevent thundering herd issue, where n concurrent requests will try to update the cache at the same time, I implemented a single-flight cache access using a distributed lock in redis. In order to ensure all concurrent requests only one will access the redis, I used a single cache key for this which is `rate_cache:lock`.

There are certain cases where stale values might be served to customers. This is just my assumption, but I am designing it under the assumption that customers should not see an HTTP error whenever possible and serving a stale value is better.

1. The Triple Rate API is down: Customers will be served the latest value in `rate_cache:entry`. In order to make sure it does not go over budget, I designed the cache to have an actual TTL more than 5 minutes.
2. The Triple Rate API is down, and the `rate_cache:entry` is empty: There is a snapshot stored in-memory for this case.

## Error Handling

The service is designed to degrade gracefully whenever possible. The table below captures the main non-happy-path scenarios, what the system does, and whether the caller receives an HTTP error.

| Scenario | Trigger / error | What happens | HTTP response |
| --- | --- | --- | --- |
| Missing required params | `period`, `hotel`, or `room` is blank | Request validation fails before any cache or downstream work starts. | `400 Bad Request` |
| Invalid enum value | `period`, `hotel`, or `room` is not one of the allowed values | Request validation fails before any cache or downstream work starts. | `400 Bad Request` |
| Budget exhausted | `BudgetGate` blocks a refresh because the daily upstream budget is used up | The service does not call the upstream API. It tries to serve a stale cached value or the in-memory snapshot if available. If none is available, it returns an error. | `200 OK` if degraded data is served; otherwise `400 Bad Request` |
| Upstream timeout / connection failure | Network timeout, DNS/socket failure, or transport exception from the upstream API | The service falls back to stale Redis cache first, then the in-memory snapshot. If neither is usable, the request fails with an upstream error. | `200 OK` if degraded data is served; otherwise `400 Bad Request` |
| Upstream non-2xx response | Upstream returns `401`, `403`, `429`, `500`, etc. | The service treats it as an upstream error and attempts the stale-cache fallback path. | `200 OK` if degraded data is served; otherwise `400 Bad Request` |
| Upstream error envelope | Upstream returns an HTTP `200` with a body containing `{ "status": "error" }` | The service treats it as an upstream failure and attempts the stale-cache fallback path. | `200 OK` if degraded data is served; otherwise `400 Bad Request` |
| Redis read failure | Redis is unavailable or read throws an exception | The service falls back to the in-memory snapshot if available. If no snapshot exists, the request proceeds to the upstream path or fails with an upstream error. | `200 OK` if snapshot data is used; otherwise `400 Bad Request` if no fallback exists |
| Redis write failure | Redis write throws an exception while storing a freshly fetched payload | The payload is still available in memory via the snapshot, so the service can continue serving it for subsequent local fallback. | No direct HTTP error; request continues with best-effort behavior |
| Malformed cached payload | Cached value is present but cannot be parsed as JSON | The service skips that entry and tries the next fallback path (stale cache, then snapshot). If nothing usable remains, the request fails. | `200 OK` if another fallback works; otherwise `400 Bad Request` |
| Missing upstream token configuration | `RATE_API_TOKEN` is not set | The request cannot be fulfilled because the upstream client cannot authenticate. This is an internal configuration error. | `500 Internal Server Error` (unhandled server-side failure) |

### Error-handling priority

When a downstream failure occurs, the service uses the following fallback order:

1. Fresh cache entry if it is still within the freshness window
2. Stale cache entry if the upstream is down or otherwise failing
3. In-memory snapshot from the current process
4. Return an error if no usable fallback exists

# Trade offs and decisions

- Q: Why fetch all rates in one API call

A: As explained earlier, it is to avoid exhausting the API budget. I also considered using a scheduler to refresh the rates in the background, but doing so doesn't provide much benefits over lazily fetching all rates in the first API call for a 5-minute window. Additionally if there are no requests for a certain period, we can conserve some API budget.

- Q: Why use Redis for pricing rates cache?

A: I also considered using purely in-memory cache for simplicity, but if the app is scaled into multiple nodes setup, then the cache will only work locally in each node and we will hit the budget limit quickly. Thus we need distributed caching

- Q: Why use single-flight mechanism, and why use redis?

A: I used single-flight mechanism when caching to prevent thundering herd issue, where n concurrent requests will try to update the cache at the same time. I also considered using a basic mutex for the concurrency control, but again, a mutex only exists locally and if the app is scaled into multiple nodes then we need distributed lock for which I use Redis

- Q: Why return stale value instead of error when upstream is down?

A: There are no hard requirements, and it depends on business requirements. But I am designing it under the assumption that customers should not see an HTTP error whenever possible and serving a stale value is better. In order to do that, I need to set the cache's actual TTL longer than 5 minutes.

# Future improvements

- Add real metrics to detect failures such as over-budget, redis or upstream API down more quickly
- Have a health check mechanism that periodically checks the service and endpoint status so we can check proactively if any dependencies are down


# AI Usage

When developing most functions, I mostly started coding the functions by myself, and used AI to give improvements and fixes on both code functionality, syntax, and structure. Also, I asked AI to help check test cases and generate ones that I missed.