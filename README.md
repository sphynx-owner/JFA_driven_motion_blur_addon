# Instructions

**For Godot 4.4 users:** I introduced a new Godot 4.4 branch with required fixes. Download from it instead.

1. Take the contents of the "addons" folder and move them to an "addons" folder in your project.
2. Add an environment node, then add a MotionBlurCompositor (NEW!!) to it.
3. Add a new PreBlurProcessor effect, which is now required. After it, add a new GuertinMotionBlur, SphynxSimpleJumpFloodMotionBlur, or ExperimentalJumpFloodMotionBlur.
4. For debugging, add "C", "Z", and "freeze" input events. Then add a DebugCompositorEffect to the compositor effects. Toggle "Debug" to true on whichever effect you want to show debug information for.

* **GuertinMotionBlur** - An all-around best blur effect, robust, performant, and now also realistic.
* **SphynxSimpleJumpFloodMotionBlur** - An effect driven by a novel dilation method using the jump flood algorithm. It is used in research of realistic blending schemes and focuses on being a retrospective blur approach.
* **ExperimentalJumpFloodMotionBlur** - An effect driven by a novel dilation method using the jump flood algorithm. It uses an added feature to heuristically fake transparency of the leading edge of the blur using the past color output.

Instructions for radial blur meshes can be seen here:
https://youtu.be/eslsw9do4Kc

**WARNING:**
If you want transparent objects to render on top of the blurred background, you can move the pre-blur-processing and blur post-process effects both to the callback type of pre-transparent. At this point, it would not work if you have MSAA enabled, so make sure to also turn that off.

# Demo Repo

You can find a working demo repository here:
https://github.com/sphynx-owner/JFA_driven_motion_blur_demo

# Sources

For a better overview of the subject, here's a video I made on it:
https://youtu.be/m_KvYlYF3sA

And here's a paper I wrote on it:
[Using the Jump Flood Algorithm to Dilate Velocity Maps in the Application of Believable High Range High Fidelity Motion Blur](https://github.com/user-attachments/files/16120346/Using.the.Jump.Flood.Algorithm.to.Dilate.Velocity.Maps.in.the.application.of.Believable.High.Range.High.Fidelity.Motion.Blur.7_7_24.2.-.Google.Docs.pdf)
