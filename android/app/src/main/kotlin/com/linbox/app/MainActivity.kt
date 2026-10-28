package com.linbox.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val PROOT_CHANNEL = "linbox/proot"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PROOT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // proot 以 libproot.so 打包在 APK 的 lib/ 目录里。
                    // targetSdk 36 下应用私有目录不允许 exec，只有 nativeLibraryDir
                    // 下的文件可执行，所以从那里启动 proot。
                    "getNativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
                    else -> result.notImplemented()
                }
            }
    }
}
