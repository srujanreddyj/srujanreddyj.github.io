---
layout: post
toc: true
title: "Why 8 Python Threads Can Still Use Only 1 Core"
categories: learnings
tags: [python, performance, concurrency, threads, processes, gil]
---

# Why 8 Python Threads Can Still Use Only 1 Core

_A simple, visual guide to CPU-bound work, the GIL, and why `ProcessPoolExecutor` sometimes beats `ThreadPoolExecutor` by a lot._

You have a batch job that takes 8 seconds.
You split it into 8 pieces.
You throw 8 threads at it.
It still takes 8 seconds.

That feels wrong the first time you see it. You reached for parallelism, paid the complexity cost, and got basically nothing back. Sometimes you even make it slower.

This is one of the most common Python performance footguns, and it happens because three ideas collide in exactly the wrong way:

- CPU-bound vs I/O-bound work
- threads vs processes
- the GIL

The good news is that once you see the pattern, you start spotting it everywhere. And the fix is often just one small change: stop using threads for CPU-bound Python work, and use processes instead.

Let's make that visible with a tiny experiment.

Imagine a batch job that transforms 8 chunks of data. Each chunk takes about 1 second of pure Python CPU work. Run them one after another, and the total time is about 8 seconds.

So far, so normal.

Then you try to speed it up with a `ThreadPoolExecutor`.

## Key Definitions

Before the experiment, here are a few quick anchors:

- **CPU-bound**: the program is slow because it is busy computing.
- **I/O-bound**: the program is slow because it is waiting on disk, network, APIs, or a database.
- **Thread**: a worker inside a process; threads share memory.
- **Process**: a separate Python interpreter with its own memory space.
- **GIL**: in CPython, the Global Interpreter Lock allows only one thread at a time to execute Python bytecode.

That is enough vocabulary to make the rest of the post click.

## Setup

Now we need a small benchmark that you can actually run.

The important thing is that `transform()` must be **real CPU work**, not `time.sleep()`. If you use sleep, you accidentally simulate waiting, which makes threads look good for the wrong reason.

```python
import time
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor

def transform(chunk):
    total = 0
    for i in range(10_000_000):
        total += i * i
    return total + chunk

chunks = list(range(8))
```

On your machine, you may need to tune the loop count so each chunk takes about 1 second.

## Runnable Benchmark

Here are the three versions side by side:

```python
## CPU
start = time.perf_counter()
results = [transform(chunk) for chunk in chunks]
print(f"Sequential: {time.perf_counter() - start:.2f}s")


## THREAD
start = time.perf_counter()
with ThreadPoolExecutor(max_workers=8) as ex:
    results = list(ex.map(transform, chunks))
print(f"Threads:    {time.perf_counter() - start:.2f}s")


## Process
start = time.perf_counter()
with ProcessPoolExecutor(max_workers=4) as ex:
    results = list(ex.map(transform, chunks))
print(f"Processes:  {time.perf_counter() - start:.2f}s")
```

On a typical machine, the threaded version is the surprise: it often stays close to the sequential runtime, while the process-based version gets a real speedup.

That is the clue that this job is CPU-bound, not I/O-bound.

## Why Threads Fail Here

The important detail is that this work is **CPU-bound**. Each worker is actively computing in Python, not waiting on the network, disk, or a database.

That runs straight into the **GIL**.

In CPython, the GIL allows only **one thread at a time** to execute Python bytecode. So even if you create 8 threads, they do not all crunch Python code at the same instant. They mostly take turns.

That means the threaded version behaves more like this:

```text
one Python process
one GIL

thread 1 -> runs
thread 2 -> waits
thread 3 -> waits
thread 4 -> waits
...

the lock gets handed around
```

You still pay extra overhead for scheduling, context switching, futures, executor bookkeeping, and contention around shared interpreter state. So you end up with almost the same total runtime as the sequential version, and sometimes slightly worse.

A simple way to picture the three approaches:

- **Sequential:** one core busy, one chunk after another.
- **Threads:** still mostly one core busy, because only one thread can hold the GIL at a time.
- **Processes:** multiple cores busy at once, because each process has its own interpreter and its own GIL.

<div class="gil-animation" data-gil-animation>
  <div class="gil-animation-tabs" role="tablist" aria-label="Executor comparison">
    <button type="button" class="is-active" data-mode="sequential">Sequential loop</button>
    <button type="button" data-mode="threads">ThreadPoolExecutor(8)</button>
    <button type="button" data-mode="processes">ProcessPoolExecutor(4)</button>
  </div>

  <div class="gil-animation-chart" aria-label="CPU core timeline animation">
    <svg viewBox="0 0 960 300" role="img" aria-labelledby="gil-animation-title gil-animation-desc">
      <title id="gil-animation-title">CPU core usage comparison</title>
      <desc id="gil-animation-desc">Sequential and threaded CPU-bound Python work mostly use one core, while process-based work uses multiple cores.</desc>
      <g class="grid">
        <line x1="160" y1="32" x2="160" y2="232"></line>
        <line x1="350" y1="32" x2="350" y2="232"></line>
        <line x1="540" y1="32" x2="540" y2="232"></line>
        <line x1="730" y1="32" x2="730" y2="232"></line>
        <line x1="920" y1="32" x2="920" y2="232"></line>
      </g>
      <g class="labels">
        <text x="96" y="70">Core 1</text>
        <text x="96" y="118">Core 2</text>
        <text x="96" y="166">Core 3</text>
        <text x="96" y="214">Core 4</text>
        <text x="160" y="266">0s</text>
        <text x="350" y="266">2s</text>
        <text x="540" y="266">4s</text>
        <text x="730" y="266">6s</text>
        <text x="920" y="266">8s</text>
      </g>
      <g class="tracks">
        <rect x="160" y="44" width="760" height="30" rx="4"></rect>
        <rect x="160" y="92" width="760" height="30" rx="4"></rect>
        <rect x="160" y="140" width="760" height="30" rx="4"></rect>
        <rect x="160" y="188" width="760" height="30" rx="4"></rect>
      </g>
      <g class="work-bars" data-bars></g>
      <line class="playhead" data-playhead x1="160" y1="32" x2="160" y2="232"></line>
    </svg>
  </div>

  <div class="gil-animation-controls">
    <button type="button" data-play>Play</button>
    <span>Wall clock</span>
    <strong data-clock>0.0s</strong>
  </div>

  <div class="gil-animation-stats" aria-live="polite">
    <div><strong data-total>8.0s</strong><span>total time</span></div>
    <div><strong data-speedup>1.0x</strong><span>speedup</span></div>
    <div><strong data-cores>1 of 4</strong><span>cores used</span></div>
  </div>

  <p class="gil-animation-callout" data-callout>
    The bug. Eight threads, but the GIL lets only one execute Python bytecode at a time. They take turns on a single core.
  </p>

  <pre class="gil-animation-code"><code data-code>with ThreadPoolExecutor(max_workers=8) as ex: ...</code></pre>

  <div class="gil-animation-legend">
    <span><i class="cpu"></i>computing (CPU)</span>
    <span><i class="ipc"></i>spawn / pickle (IPC)</span>
    <span><i class="idle"></i>idle core</span>
  </div>
</div>

<style>
  .gil-animation {
    --bg: #050504;
    --panel: #242522;
    --track: #252621;
    --ink: #f4f1ea;
    --muted: #c9c5bb;
    --line: #e8e3d8;
    --cpu: #16a085;
    --ipc: #ef7d61;
    margin: 2rem 0;
    padding: 1.25rem;
    color: var(--ink);
    background: var(--bg);
    border-radius: 8px;
    overflow: hidden;
  }

  .gil-animation-tabs,
  .gil-animation-controls,
  .gil-animation-stats,
  .gil-animation-legend {
    display: flex;
    gap: 0.75rem;
    align-items: center;
    flex-wrap: wrap;
  }

  .gil-animation button {
    color: var(--ink);
    background: transparent;
    border: 2px solid var(--line);
    border-radius: 8px;
    padding: 0.55rem 1rem;
    font: inherit;
    font-weight: 700;
    cursor: pointer;
  }

  .gil-animation button.is-active {
    background: var(--ink);
    color: var(--bg);
  }

  .gil-animation-chart {
    margin-top: 1.25rem;
  }

  .gil-animation svg {
    display: block;
    width: 100%;
    height: auto;
  }

  .gil-animation .grid line,
  .gil-animation .playhead {
    stroke: var(--line);
    stroke-width: 1.25;
  }

  .gil-animation .playhead {
    opacity: 0.9;
  }

  .gil-animation .labels text {
    fill: var(--muted);
    font-size: 18px;
    font-weight: 700;
    text-anchor: end;
  }

  .gil-animation .labels text:nth-last-child(-n+5) {
    text-anchor: middle;
  }

  .gil-animation .tracks rect {
    fill: var(--track);
  }

  .gil-animation .work-bars rect.cpu {
    fill: var(--cpu);
  }

  .gil-animation .work-bars rect.ipc {
    fill: var(--ipc);
  }

  .gil-animation-controls {
    margin-top: 0.75rem;
    font-weight: 700;
  }

  .gil-animation-controls strong {
    font-family: monospace;
    font-size: 1.25rem;
  }

  .gil-animation-stats {
    margin-top: 1rem;
  }

  .gil-animation-stats div {
    flex: 1 1 12rem;
    min-width: 0;
    padding: 0.85rem 1rem;
    background: var(--panel);
    border-radius: 6px;
  }

  .gil-animation-stats strong,
  .gil-animation-stats span {
    display: block;
  }

  .gil-animation-stats strong {
    font-family: monospace;
    font-size: clamp(1.35rem, 4vw, 2rem);
  }

  .gil-animation-stats span {
    color: var(--muted);
    font-weight: 700;
  }

  .gil-animation-callout {
    margin: 1rem 0 0;
    padding: 1rem;
    background: var(--panel);
    border-left: 5px solid #ef4444;
    border-radius: 6px;
    font-weight: 700;
  }

  .gil-animation-code {
    margin: 1rem 0 0;
    color: var(--muted);
    background: transparent;
    border: 0;
    padding: 0;
  }

  .gil-animation-legend {
    margin-top: 0.85rem;
    color: var(--muted);
    font-weight: 700;
  }

  .gil-animation-legend i {
    display: inline-block;
    width: 1rem;
    height: 1rem;
    margin-right: 0.4rem;
    border-radius: 3px;
    vertical-align: -0.15rem;
  }

  .gil-animation-legend .cpu {
    background: var(--cpu);
  }

  .gil-animation-legend .ipc {
    background: var(--ipc);
  }

  .gil-animation-legend .idle {
    border: 1px solid var(--muted);
  }

  @media (max-width: 640px) {
    .gil-animation {
      padding: 0.85rem;
    }

    .gil-animation button {
      width: 100%;
    }

    .gil-animation .labels text {
      font-size: 15px;
    }
  }
</style>

<script>
  (function () {
    var root = document.querySelector("[data-gil-animation]");
    if (!root) return;

    var chartStart = 160;
    var chartWidth = 760;
    var rowY = [44, 92, 140, 188];
    var barHeight = 30;
    var duration = 1600;
    var activeMode = "sequential";
    var raf = null;

    var modes = {
      sequential: {
        total: 8.0,
        speedup: "1.0x",
        cores: "1 of 4",
        code: "results = [transform(chunk) for chunk in chunks]",
        callout: "Sequential baseline. One core works through the chunks one after another. Simple, predictable, and not parallel.",
        bars: [
          { core: 0, start: 0.0, end: 8.0, type: "cpu" }
        ]
      },
      threads: {
        total: 8.2,
        speedup: "1.0x",
        cores: "1 of 4",
        code: "with ThreadPoolExecutor(max_workers=8) as ex: ...",
        callout: "The bug. Eight threads, but the GIL lets only one execute Python bytecode at a time. They take turns on a single core.",
        bars: [
          { core: 0, start: 0.0, end: 1.0, type: "cpu" },
          { core: 0, start: 1.0, end: 2.0, type: "cpu" },
          { core: 0, start: 2.0, end: 3.0, type: "cpu" },
          { core: 0, start: 3.0, end: 4.0, type: "cpu" },
          { core: 0, start: 4.0, end: 5.0, type: "cpu" },
          { core: 0, start: 5.0, end: 6.0, type: "cpu" },
          { core: 0, start: 6.0, end: 7.0, type: "cpu" },
          { core: 0, start: 7.0, end: 8.0, type: "cpu" }
        ]
      },
      processes: {
        total: 2.2,
        speedup: "3.6x",
        cores: "4 of 4",
        code: "with ProcessPoolExecutor(max_workers=4) as ex: ...",
        callout: "Real parallelism. Four processes each bring their own interpreter and GIL, so four chunks can run at the same time.",
        bars: [
          { core: 0, start: 0.0, end: 0.2, type: "ipc" },
          { core: 1, start: 0.0, end: 0.2, type: "ipc" },
          { core: 2, start: 0.0, end: 0.2, type: "ipc" },
          { core: 3, start: 0.0, end: 0.2, type: "ipc" },
          { core: 0, start: 0.2, end: 1.1, type: "cpu" },
          { core: 1, start: 0.2, end: 1.1, type: "cpu" },
          { core: 2, start: 0.2, end: 1.1, type: "cpu" },
          { core: 3, start: 0.2, end: 1.1, type: "cpu" },
          { core: 0, start: 1.1, end: 2.0, type: "cpu" },
          { core: 1, start: 1.1, end: 2.0, type: "cpu" },
          { core: 2, start: 1.1, end: 2.0, type: "cpu" },
          { core: 3, start: 1.1, end: 2.0, type: "cpu" },
          { core: 0, start: 2.0, end: 2.2, type: "ipc" },
          { core: 1, start: 2.0, end: 2.2, type: "ipc" },
          { core: 2, start: 2.0, end: 2.2, type: "ipc" },
          { core: 3, start: 2.0, end: 2.2, type: "ipc" }
        ]
      }
    };

    function xAt(seconds) {
      return chartStart + (seconds / 8) * chartWidth;
    }

    function render(mode, progress) {
      var data = modes[mode];
      var bars = root.querySelector("[data-bars]");
      bars.innerHTML = "";

      data.bars.forEach(function (bar) {
        var visibleEnd = Math.min(bar.end, progress * data.total);
        if (visibleEnd <= bar.start) return;
        var rect = document.createElementNS("http://www.w3.org/2000/svg", "rect");
        rect.setAttribute("x", xAt(bar.start));
        rect.setAttribute("y", rowY[bar.core]);
        rect.setAttribute("width", Math.max(2, xAt(visibleEnd) - xAt(bar.start)));
        rect.setAttribute("height", barHeight);
        rect.setAttribute("rx", 4);
        rect.setAttribute("class", bar.type);
        bars.appendChild(rect);
      });

      root.querySelector("[data-playhead]").setAttribute("x1", xAt(Math.min(8, progress * data.total)));
      root.querySelector("[data-playhead]").setAttribute("x2", xAt(Math.min(8, progress * data.total)));
      root.querySelector("[data-clock]").textContent = (progress * data.total).toFixed(1) + "s";
      root.querySelector("[data-total]").textContent = data.total.toFixed(1) + "s";
      root.querySelector("[data-speedup]").textContent = data.speedup;
      root.querySelector("[data-cores]").textContent = data.cores;
      root.querySelector("[data-callout]").textContent = data.callout;
      root.querySelector("[data-code]").textContent = data.code;
    }

    function setMode(mode) {
      activeMode = mode;
      if (raf) cancelAnimationFrame(raf);
      root.querySelectorAll("[data-mode]").forEach(function (button) {
        button.classList.toggle("is-active", button.getAttribute("data-mode") === mode);
      });
      render(mode, 0);
      root.querySelector("[data-clock]").textContent = "0.0s";
      root.querySelector("[data-play]").textContent = "Play";
    }

    function play() {
      if (raf) cancelAnimationFrame(raf);
      var start = performance.now();
      root.querySelector("[data-play]").textContent = "Replay";

      function tick(now) {
        var progress = Math.min(1, (now - start) / duration);
        render(activeMode, progress);
        if (progress < 1) {
          raf = requestAnimationFrame(tick);
        }
      }

      raf = requestAnimationFrame(tick);
    }

    root.querySelectorAll("[data-mode]").forEach(function (button) {
      button.addEventListener("click", function () {
        setMode(button.getAttribute("data-mode"));
      });
    });

    root.querySelector("[data-play]").addEventListener("click", play);
    setMode(activeMode);
  })();
</script>

In other words, the threads are real, but for pure Python CPU work, they still have to queue up for the interpreter.

## Why Processes Work Better

`ProcessPoolExecutor` sidesteps the GIL by using **separate processes** instead of threads.

That matters because each process gets:

- its **own Python interpreter**
- its **own memory space**
- its **own GIL**

So on a 4-core machine, 4 chunks can genuinely run at the same time. That is real parallelism, not just concurrency.

Threads share one interpreter. Processes each bring their own.

The mental model becomes:

```text
process 1 -> GIL 1 -> chunk 1
process 2 -> GIL 2 -> chunk 2
process 3 -> GIL 3 -> chunk 3
process 4 -> GIL 4 -> chunk 4
```

That is why `ProcessPoolExecutor` can produce a real speedup for this benchmark.

## Why the Speedup Is Real, But Not Perfect

The process version does not usually give you a perfect 8x win. Two limits matter.

### 1. Core Count Sets the Ceiling

If you have 8 tasks but only 4 cores, the work has to happen in two waves.

So the best possible speedup is closer to 4x than 8x.

### 2. Moving Data Between Processes Costs Time

Processes do not share Python objects directly the way threads do.

That means inputs and outputs have to be:

- serialized with pickle
- sent to worker processes
- sent back again

Starting processes is also heavier than starting threads.

That overhead is why process pools shine on **big enough tasks**, but can disappoint on tiny ones.

Process pools buy real parallelism, but you pay for it in startup cost and data movement.

## How to Recognize This Bug in Real Code

Usually the first clue is simple: adding threads does nothing.

If you increase `max_workers` and the runtime barely changes, that is a strong sign the slow part is not waiting on I/O. It is busy computing.

A few practical signs:

- One CPU core is pinned near 100%.
- The other cores are mostly quiet.
- Profiling shows time spent in your Python transform function, not in network or disk calls.
- More threads add overhead, but not speed.

If more threads do not help, stop asking "how do I parallelize this?" and start asking "what kind of work is this?"

## Threads Are Still Useful

This is not an anti-thread post. Threads are great when the program spends most of its time waiting.

For example:

- an API
- a database
- the filesystem
- the network

In those cases, one thread can wait while another thread makes progress. The GIL is much less painful because waiting on I/O often releases it.

Same executor pattern, opposite result: threads are great for waiting, but poor for pure Python computing.

That is why this version would be misleading:

```python
def transform(chunk):
    time.sleep(1)
    return chunk
```

If you benchmark that with threads, it will look great. But you did not test CPU-bound work. You tested waiting.

And threads are excellent at waiting.

## The Rule of Thumb

When choosing between threads and processes, ask what your program is mostly doing.

If it is mostly waiting:

```text
network, disk, database, API, sleep
```

Use threads or async I/O.

If it is mostly computing:

```text
parsing, compression, image transforms, pure Python loops, feature extraction
```

Use processes, native extensions, vectorized libraries, or a distributed compute system.

The shortest version is:

> Threads for waiting. Processes for working.

Or even shorter:

- **CPU-bound:** usually use processes.
- **I/O-bound:** often use threads.

## One More Caveat

Some CPU-heavy Python libraries do not behave like the toy benchmark above.

Libraries like NumPy, Polars, PyTorch, TensorFlow, and many compression or image-processing libraries often push the expensive work into native code. That native code may release the GIL or use its own thread pools.

So the real question is not just "is my task CPU-heavy?"

It is:

> Is my CPU-heavy work executing as Python bytecode, or inside native code that can run outside the GIL?

For pure Python loops, the GIL matters a lot. For native libraries, benchmark before assuming.

## Final Takeaway

Adding threads does not automatically make Python CPU work run in parallel.

If your workload is pure Python computation, `ThreadPoolExecutor` can leave you staring at one busy core and seven disappointed expectations. `ProcessPoolExecutor` works better because each worker process gets its own interpreter and its own GIL.

That is the performance lesson:
- Use threads when the program is waiting.
- Use processes when the program is working.
