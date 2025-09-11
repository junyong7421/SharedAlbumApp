package com.example.sharedalbumapp

import android.graphics.BitmapFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult

import java.nio.ByteBuffer
import java.nio.ByteOrder   // 👈 추가

class MainActivity : FlutterActivity() {

  private val CHANNEL = "face_landmarker"
  private var landmarker: FaceLandmarker? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
      .setMethodCallHandler { call, result ->
        when (call.method) {

          "loadModel" -> {
            try {
              val args = call.arguments as Map<*, *>
              val taskBytes = args["task"] as ByteArray
              val maxFaces = (args["maxFaces"] as? Int) ?: 5

              // ---- 핵심 수정: direct ByteBuffer 로 변환 ----
              val direct = ByteBuffer
                .allocateDirect(taskBytes.size)
                .order(ByteOrder.nativeOrder())
              direct.put(taskBytes)
              direct.rewind()
              // --------------------------------------------

              val base = BaseOptions.builder()
                .setModelAssetBuffer(direct)  // heap 아님!
                .build()

              val options = FaceLandmarker.FaceLandmarkerOptions.builder()
                .setBaseOptions(base)
                .setRunningMode(RunningMode.IMAGE)
                .setNumFaces(maxFaces)
                .build()

              landmarker?.close()
              landmarker = FaceLandmarker.createFromOptions(this, options)
              result.success(true)
            } catch (e: Exception) {
              result.error("LOAD_FAIL", e.message, null)
            }
          }

          "detect" -> {
            try {
              val args = call.arguments as Map<*, *>
              val imageBytes = args["image"] as ByteArray
              val lm = landmarker ?: run {
                result.error("NO_MODEL", "Call loadModel() first.", null)
                return@setMethodCallHandler
              }
              val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
              val mpImage: MPImage = BitmapImageBuilder(bitmap).build()
              val out: FaceLandmarkerResult = lm.detect(mpImage)

              val faces = mutableListOf<List<Map<String, Double>>>()
              out.faceLandmarks()?.forEach { list ->
                val pts = list.map { pt -> mapOf("x" to pt.x().toDouble(), "y" to pt.y().toDouble()) }
                faces.add(pts)
              }
              result.success(faces)
            } catch (e: Exception) {
              result.error("DETECT_FAIL", e.message, null)
            }
          }

          "close" -> {
            try {
              landmarker?.close()
              landmarker = null
              result.success(true)
            } catch (e: Exception) {
              result.error("CLOSE_FAIL", e.message, null)
            }
          }

          else -> result.notImplemented()
        }
      }
  }

  override fun onDestroy() {
    landmarker?.close()
    landmarker = null
    super.onDestroy()
  }
}
