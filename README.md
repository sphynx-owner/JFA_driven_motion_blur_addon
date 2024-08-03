# Instructions
1. take the contents of the "addons" folder and move them to an addons folder in your project. 
2. add an environment node, add a compositor effect to it
3. to that, add a new PreBlurProcessor effect, which is now required, and after it add a new MotionBlurSphynxJumpFlood

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
