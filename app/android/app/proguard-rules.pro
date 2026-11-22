# Release builds are shrunk and renamed by R8 (the Flutter Gradle plugin turns it on and adds this file). ONNX
# Runtime's native binding (libonnxruntime4j_jni.so) looks its Java classes up by name (FindClass "ai/onnxruntime/
# TensorInfo", "OrtException", "OnnxTensor", ...), so R8 must neither rename nor remove any of them. Without this, the
# safety classifier loaded, and the first message of a session crashed the app: "JNI DETECTED ERROR IN APPLICATION:
# java_class == null in call to GetMethodID from ai.onnxruntime.OrtSession.run", after ClassNotFoundException
# ai.onnxruntime.TensorInfo (R8 had renamed it w70; arm64 emulator, 2026-11-14, L-5).
# app/android/app/build.gradle.kts checks R8's mapping after every release build.
-keep class ai.onnxruntime.** { *; }
