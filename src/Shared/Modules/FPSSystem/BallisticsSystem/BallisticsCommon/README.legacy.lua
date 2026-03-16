--[[

# Solvers — Developer Reference

## What is a Solver?

In this FPS framework, a **Solver** is the module responsible for deciding how a bullet moves through the world. When a weapon fires, it doesn't manage its own physics — it delegates that entirely to a Solver. The Solver owns the trajectory logic, the raycasting, and the lifecycle of the projectile from the moment it leaves the barrel to the moment it stops.

There are four Solvers in total. Each one models a fundamentally different physical behaviour, and choosing the right one is about matching the mental model of the weapon to the mental model of the physics.

---

## The Shared Contract: BulletContext

Every Solver is bound to a **BulletContext**. This is the most important concept to understand before working with any Solver.

When a weapon fires, it creates a `BulletContext` — a lightweight object that carries the bullet's identity, its initial state (origin, direction, speed), and its runtime state (current position, velocity, whether it's still alive). The Solver receives this context and uses it as both an input and an output channel. The Solver reads the initial state to know where to start, and writes back to it every frame via `_UpdateState()` so the rest of the game always knows where the bullet currently is.

This separation is deliberate. Weapon code never talks to the Solver directly after firing — it listens to the Solver's **Signals** and reads state from the BulletContext. This means you can swap one Solver for another without touching any weapon code, as long as the signals you care about are available.

The BulletContext also maintains a `Trajectory` table — a list of positions appended to every frame. This is what makes lag compensation possible, since you can rewind through the trajectory to find where a bullet was at any past moment in time.

---

## The Four Solvers

### BounceSolver

The BounceSolver simulates a projectile that travels under gravity and **reflects off surfaces** when it collides with them. It is the most computationally sophisticated of the four, and the one most likely to be used for grenade-like or ricochet-based projectiles.

Under the hood, it runs on a `ConnectParallel` heartbeat — meaning the heavy raycast and kinematic math runs in parallel across all active projectiles simultaneously, and only synchronizes back to the main thread when it needs to write Instance properties or fire Signals. This makes it scale well under high fire rates.

It has a High-Fidelity mode that subdivides each frame's movement into smaller sub-slices for more accurate contact point and surface normal detection. Because more accurate normals mean more realistic bounce angles, this directly improves the quality of ricochet behaviour. The sub-slice count scales with projectile speed and adapts automatically if the budget is exceeded.

Three layered guards protect against corner traps — situations where a projectile bounces between two closely-facing surfaces indefinitely. The guards check elapsed simulation time between bounces, the geometric alignment of consecutive bounce normals, and total displacement across a frame. Any one of them is sufficient to terminate a trapped projectile cleanly.

**Signals fired:** `OnTravel`, `OnHit`, `OnBounce`, `OnTerminated`.

---

### HitscanSolver

The HitscanSolver represents the simplest physical model: the bullet **arrives instantly**. There is no simulation loop, no heartbeat connection, and no frame-by-frame position tracking. When `Fire()` is called, the entire raycast chain completes synchronously in that same call.

It supports multi-hit penetration through a pierce callback. If the provided `CanPierceFunction` returns true for a hit surface, the Solver re-fires the ray from just past the impact point, excluding the pierced instance, and continues until it hits something it cannot penetrate or exhausts the maximum distance. All hit and pierce signals are collected during the parallel raycast phase and replayed in order after `task.synchronize()`.

The design is intentionally parallel-aware: `Fire()` can be batched inside a `ConnectParallel` heartbeat so that many simultaneous hitscan shots perform their raycasts in parallel. When called from a normal serial script, `task.synchronize()` is a no-op, so there is no overhead.

**Signals fired:** `OnHit`, `OnPierce`, `OnTerminated`.

---

### ProjectileSolver

The ProjectileSolver delegates everything to **FastCast**, an established Roblox projectile library. It acts as a thin adapter layer that translates FastCast's internal events (`RayHit`, `LengthChanged`, `CastTerminating`) into the same Signal interface the rest of the framework expects.

This is the right choice when you want arc-based projectile flight with gravity but don't need bouncing or real physics interaction. It is the most battle-tested of the four in terms of the underlying simulation engine, and supports pierce through FastCast's `CanPierceFunction` natively.

Internally it maintains two weak-keyed maps — `ContextToCast` and `CastToContext` — so either object can be looked up from the other without preventing garbage collection of terminated contexts.

**Signals fired:** `OnTravel`, `OnHit`, `OnPierce`, `OnTerminated`.

---

### PhysicsSolver

The PhysicsSolver is the odd one out. Rather than controlling the bullet's position mathematically, it hands the projectile over to **Roblox's physics engine** as an unanchored, collidable part. Gravity, bouncing, rolling, being deflected by explosions — all of this is handled by the engine without any kinematic math in the Solver itself.

The Solver's job is then to monitor what the physics engine is doing: it raycasts from the bullet's last known position to its current position each frame to detect surfaces it passed through, fires `OnHit` when a contact is detected, and enforces lifetime and distance limits since the physics engine has no concept of those.

A `hitCache` table prevents the same surface from firing `OnHit` multiple times in rapid succession due to physics jitter — each instance is rate-limited to one hit signal per `HIT_COOLDOWN` seconds.

The tradeoff is predictability. Because the physics engine controls the trajectory, behaviour is non-deterministic across server and client, which makes lag compensation harder. Use this Solver when physical authenticity matters more than precision — thrown objects, rolling grenades, or debris.

**Signals fired:** `OnHit`, `OnTerminated`.

---

## Choosing a Solver

The decision comes down to two questions: does the bullet need to persist across frames, and does it need to interact with the physics world?

A hitscan weapon like a sniper rifle fires and forgets in a single frame — use `HitscanSolver`. 
A rocket or grenade that arcs through the air over several seconds but doesn't interact with physics — use `ProjectileSolver`. 
A bouncing grenade that ricochets off walls — use `BounceSolver`.
A thrown physics object that rolls and tumbles — use `PhysicsSolver`.

---

## Extending the System

All four Solvers follow the same minimal interface: a `Fire(context, behavior)` method, a `Signals` table, 
and a `Destroy()` lifecycle method. If you need a fifth Solver — say, one that simulates drag, or one that curves toward a target — 
you implement the same interface and the rest of the weapon framework requires no changes. 
The BulletContext is the stable contract between weapons and Solvers; keep that contract intact and the Solver internals are yours to build however the physics demand.
	
]]