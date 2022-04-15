# gleam_tcp

There is definitely a bug... I don't think the socket is getting closed
correctly... I tried adding a `gen_tcp:shutdown` call, but that doesn't seem
to fix it.  Still need to investigate.

```fish
~/gleams/gleam_tcp on  master [!] ☷  wrk -t12 -c400 -d30s http://localhost:8000/
Running 30s test @ http://localhost:8000/
  12 threads and 400 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency    10.99ms   75.35ms   1.91s    96.72%
    Req/Sec     1.35k     1.64k   17.87k    85.37%
  264755 requests in 30.09s, 4.54MB read
  Socket errors: connect 0, read 264770, write 0, timeout 14
Requests/sec:   8799.46
Transfer/sec:    154.68KB
```
