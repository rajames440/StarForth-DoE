# DOE heartbeat comparison

Compiled from summary_statistics.csv files on three runs. Metrics are means over all observations.

## A_B_C_FULL

| Metric | DOE_01 | DOE_02 | DOE_03 |
| --- | --- | --- | --- |
| Cache hit % | 23.41 | 22.76 | 22.74 |
| Bucket hit % | 58.62 | 59.27 | 59.29 |
| Cache hit latency (ns) | 32.77 | 33.53 | 34.44 |
| Bucket search latency (ns) | 54.82 | 55.53 | 55.36 |
| VM workload ns (q48) | 348.47e9 | 379.78e9 | 386.50e9 |


## A_B_CACHE

| Metric | DOE_01 | DOE_02 | DOE_03 |
| --- | --- | --- | --- |
| Cache hit % | 18.39 | 17.44 | 17.62 |
| Bucket hit % | 63.64 | 64.59 | 64.41 |
| Cache hit latency (ns) | 28.23 | 30.23 | 29.19 |
| Bucket search latency (ns) | 50.80 | 52.40 | 51.06 |
| VM workload ns (q48) | 261.90e9 | 288.77e9 | 280.93e9 |


## A_BASELINE

| Metric | DOE_01 | DOE_02 | DOE_03 |
| --- | --- | --- | --- |
| Cache hit % | 0.00 | 0.00 | 0.00 |
| Bucket hit % | 0.00 | 0.00 | 0.00 |
| Cache hit latency (ns) | 0.00 | 0.00 | 0.00 |
| Bucket search latency (ns) | 0.00 | 0.00 | 0.00 |
| VM workload ns (q48) | 248.65e9 | 272.56e9 | 279.53e9 |

