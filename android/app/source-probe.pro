# A single opt-in entry point lets R8 process the fixture and native engine
# together. Separate instrumentation must not call stripped Kotlin helpers.
-keep class org.mewx.wenku8_flutter.SourceFixtureProbe { public *; }
