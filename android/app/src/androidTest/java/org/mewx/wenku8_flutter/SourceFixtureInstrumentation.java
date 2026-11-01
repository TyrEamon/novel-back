package org.mewx.wenku8_flutter;

import android.app.Activity;
import android.app.Instrumentation;
import android.os.Bundle;

/** No Kotlin/runtime-library calls cross the independently shrunk APK boundary. */
public class SourceFixtureInstrumentation extends Instrumentation {
    private boolean interactive;
    private boolean loginOnly;
    private boolean runtimeOnly;
    private boolean completion;
    @Override public void onCreate(Bundle arguments) { super.onCreate(arguments); interactive = "true".equals(arguments.getString("interactive")); loginOnly = "true".equals(arguments.getString("loginOnly")); runtimeOnly = "true".equals(arguments.getString("runtimeOnly")); completion = "true".equals(arguments.getString("completion")); start(); }
    @Override public void onStart() {
        Bundle results = new Bundle();
        int code = Activity.RESULT_CANCELED;
        try {
            // The production/debug host intentionally excludes opt-in source
            // probes. Keep this test runner compilable without bundling them.
            Class<?> probe = Class.forName("org.mewx.wenku8_flutter.SourceFixtureProbe", true, getTargetContext().getClassLoader());
            String report = (String) (completion || runtimeOnly
                ? probe.getMethod(completion ? "completion" : "runtimeOnly", android.content.Context.class).invoke(null, getTargetContext())
                : probe.getMethod("run", android.content.Context.class, boolean.class, boolean.class).invoke(null, getTargetContext(), interactive, loginOnly));
            results.putString("stream", report);
            if (!report.contains("\"failed\"")) code = Activity.RESULT_OK;
        } catch (Throwable error) {
            results.putString("stream", "SOURCE_FIXTURE_FAILED=" + error.getClass().getSimpleName());
        }
        finish(code, results);
    }
}
