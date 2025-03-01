# ccev
Cooperative multi-tasking library for ComputerCraft and similar

## what is cooperative multi-tasking
In this case, multiple threads can exist at the same time, but the threads have to bee cooperative,
which means that they have tell the scheduler to switch to another thread for a bit

## features
- Threads
- Signals
- Channels
- Timers

This library is built for having a lot of threads, where most of them are waiting. Waiting threads do not affect performance **at all**

## documentation
see [docs.txt](./docs.txt)
