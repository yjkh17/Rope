# Rope

## Project Overview
Rope is a macOS application that renders a physics-driven rope or strand that remains attached to the mouse cursor. The rope follows cursor motion with gravity, inertia, and constraint-based physics to stay taut while reacting naturally to movement. Rendering occurs in a transparent, click-through overlay window, and the experience is only active while the Mac is unlocked and in use.

## Key Features
- Cursor-anchored rope
- Verlet physics integration
- Gravity with damping
- Fixed-length segment constraints
- Transparent overlay window
- Click-through behavior that does not block mouse or keyboard input
- No global event hooks
- No Accessibility permissions required

## How It Works (Technical)
- **Mouse tracking strategy:** The app polls `NSEvent.mouseLocation` rather than listening to global mouse events. Polling avoids installing global hooks or requiring Accessibility permissions while still providing smooth cursor position data for the physics solver.
- **Overlay window design:** A borderless overlay window is raised to `.screenSaver` level and configured with `ignoresMouseEvents = true` so it is click-through. The window is transparent, allowing the rope to render above other content without intercepting input.
- **Rope data structure:** The rope is modeled as a list of nodes, each storing its current and previous positions. These pairs support Verlet integration while keeping the rope lightweight to update.
- **Verlet integration:** Each frame, node positions advance using their previous positions and applied forces (gravity and damping) to approximate acceleration-free physics with minimal numerical instability.
- **Constraint solver:** After integration, segment-length constraints iterate along the rope to enforce a fixed distance between adjacent nodes, keeping the rope taut and preventing stretching.
- **Coordinate conversion:** Screen-space cursor positions are converted to window coordinates, then to the view’s coordinate system for rendering and physics updates, ensuring the rope aligns with the onscreen cursor.
- **Flipped coordinates:** The main drawing view sets `isFlipped = true`, aligning its coordinate system with AppKit’s top-left origin to simplify mapping from screen coordinates and drawing calculations.

## Project Structure
- **`AppDelegate.swift`** – Launches the overlay window and coordinates app lifecycle.
- **`OverlayWindow.swift`** – Defines the transparent, click-through overlay window at screen-saver level.
- **`RopeView.swift`** – Contains rope physics, constraint solver, and rendering code.

## Running the Project
1. Open the project in Xcode.
2. Select the macOS target.
3. Run the application.
4. Move the cursor to see the rope follow your motion.
5. Quit the app to remove the overlay.

The app must remain running for the rope to appear, and the rope disappears when the app exits.

## Limitations
- Does not operate on the lock screen or login screen.
- Rope is purely visual; no user interaction is captured.
- Overlay exists only while the application runs.

## Possible Extensions
- Chain or link-style rendering.
- Tapered thickness along the rope.
- Smooth spline-based rendering.
- Multiple simultaneous ropes.
- Color or glow effects.
- Metal-based rendering pipeline.
