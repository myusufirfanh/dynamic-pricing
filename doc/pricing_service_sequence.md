# PricingService API sequence

```mermaid
sequenceDiagram
    participant Client
    participant Controller as PricingController
    participant Service as PricingService
    participant Budget as BudgetGate
    participant Cache as RateCache
    participant Upstream as RateApiClient
    participant API as Rate API

    Client->>Controller: Request pricing for a combination
    Controller->>Service: Handle request

    Service->>Cache: Read cached entry
    alt Fresh cache entry exists
        Cache-->>Service: Return fresh entry
        Service-->>Controller: Return rate from cache
        Controller-->>Client: Success response
    else Cache is stale or missing
        Service->>Budget: Check whether refresh is allowed
        alt Budget exhausted
            Budget-->>Service: Refresh blocked
            Service->>Cache: Try stale cached entry
            alt Stale cache exists
                Cache-->>Service: Return stale entry
                Service-->>Controller: Return stale rate
                Controller-->>Client: Success response with stale data
            else No stale cache
                Service->>Cache: Try in-memory snapshot
                alt Snapshot exists
                    Cache-->>Service: Return snapshot entry
                    Service-->>Controller: Return snapshot rate
                    Controller-->>Client: Success response with snapshot data
                else No fallback
                    Service-->>Controller: Return error response
                    Controller-->>Client: Error response
                end
            end
        else Budget available
            Budget-->>Service: Refresh allowed
            Service->>Cache: Acquire distributed lock
            alt Lock acquired
                Cache->>Upstream: Fetch batch rates
                Upstream->>API: POST /pricing

                alt Successful response
                    API-->>Upstream: 2xx with rates payload
                    Upstream-->>Service: Return fresh data
                    Service->>Cache: Write fresh entry to cache
                    Cache-->>Service: Cache updated
                    Service-->>Controller: Return rate
                    Controller-->>Client: Success response
                else Downstream error
                    API-->>Upstream: 4xx/5xx or {"status":"error"}
                    Upstream-->>Service: Raise upstream error
                    Service->>Cache: Try stale cached entry
                    alt Stale cache exists
                        Cache-->>Service: Return stale entry
                        Service-->>Controller: Return stale rate
                        Controller-->>Client: Success response with stale data
                    else No stale cache
                        Service->>Cache: Try in-memory snapshot
                        alt Snapshot exists
                            Cache-->>Service: Return snapshot entry
                            Service-->>Controller: Return snapshot rate
                            Controller-->>Client: Success response with snapshot data
                        else No fallback
                            Service-->>Controller: Return error response
                            Controller-->>Client: Error response
                        end
                    end
                end
            else Lock already held
                Cache->>Cache: Wait briefly for winner
                Cache-->>Service: Return entry from Redis or snapshot
                Service-->>Controller: Return rate or fallback result
                Controller-->>Client: Response
            end
        end
    end
```

## Notes

- The service checks whether the cached entry is fresh before deciding to serve it directly.
- If a refresh is needed, the budget gate decides whether the upstream call is allowed.
- The cache layer uses a Redis-backed single-flight lock so only one pod updates the shared cache entry at a time.
- When the downstream API fails, the service degrades gracefully by serving stale cache data first, then the in-memory snapshot, and only then returning an error.
