# Instructions
**For Godot 4.4 users:** I introduced a new Godot 4.4 branch with required fixes, download from it instead.

1. take the contenst of the "addons" folder and move them to an addons folder in your project. 
2. add an environment node, add a MotionBlurCompositor(NEW!!) to it
3. to that, add a new PreBlurProcessor effect, which is now required, and after it add a new GuertinMotionBlur, SphynxSimpleJumpFloodMotionBlur, or ExperimentalJumpFloodMotionBlur
4. for debugging, add a "C","Z", and "freeze" input events, and then a DebugCompositorEffect to the compositor effects. Then, all you have to do is toggle "Debug" to true on whichever effect you want to show debug for

* GuretinMotionBlur - An all around best blur effect, robust, performant, and now also realistic.
* SphynxSimpleJumpFloodMotionBlur - An effect driven by a novel dilation method using the jump flood algorithm, used in research of realistic blending schemes and focused on being a retrospective blur approach.
* ExperimentalJumpFloodMotionBlur - An effect driven by a novel dilation method using the jump flood algorithm, uses an added feature to heuristically fake transparency of leading edge of the blur using the past color output.

instructions for radial blur meshes can be seen here:
https://youtu.be/eslsw9do4Kc

WARNING:
if you want transparent objects to render on top of the blurred background, you can move the pre-blur-processing and blur post process effects both to callback type of pre-transparent, At which point it would not work if you have MSAA enabled, so make sure to also turn that off.

# Demo Repo
you can find a working demo repository here:
https://github.com/sphynx-owner/JFA_driven_motion_blur_demo

# Sources
for a better overview of the subject here's a video I made on it:
https://youtu.be/m_KvYlYF3sA
and heres a paper I wrote on it:
[Using.the.Jump.Flood.Algorithm.to.Dilate.Velocity.Maps.in.the.application.of.Believable.High.Range.High.Fidelity.Motion.Blur.7_7_24.2.-.Google.Docs.pdf](https://github.com/user-attachments/files/16120346/Using.the.Jump.Flood.Algorithm.to.Dilate.Velocity.Maps.in.the.application.of.Believable.High.Range.High.Fidelity.Motion.Blur.7_7_24.2.-.Google.Docs.pdf)
