package com.example.camera_app

import android.media.MediaScannerConnection
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Calendar
import java.util.TimeZone

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.camera_app/media_scanner"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanFile" -> {
                    val filePath = call.argument<String>("path")
                    if (filePath != null) {
                        MediaScannerConnection.scanFile(
                            applicationContext,
                            arrayOf(filePath),
                            null
                        ) { _, _ ->
                            // Callback khi scan xong
                        }
                        result.success(true)
                    } else {
                        result.error("INVALID_PATH", "File path is null", null)
                    }
                }
                "getDeviceInfo" -> {
                    val info = mapOf(
                        "manufacturer" to android.os.Build.MANUFACTURER,
                        "model" to android.os.Build.MODEL,
                        "device" to android.os.Build.DEVICE,
                        "brand" to android.os.Build.BRAND
                    )
                    result.success(info)
                }
                // Ghi GPS tọa độ vào EXIF bằng ExifInterface.setLatLong() chuẩn Android
                // Google Photos sẽ đọc được vị trí từ field này
                "writeGpsToExif" -> {
                    try {
                        val filePath = call.argument<String>("path")
                        val latitude = call.argument<Double>("latitude")
                        val longitude = call.argument<Double>("longitude")
                        val altitude = call.argument<Double>("altitude") ?: 0.0
                        // Nguồn vị trí: "GPS" (vệ tinh) hoặc "NETWORK" (mạng/WiFi)
                        val provider = call.argument<String>("provider") ?: "GPS"

                        if (filePath == null || latitude == null || longitude == null) {
                            result.error("INVALID_ARGS", "path, latitude hoặc longitude bị null", null)
                            return@setMethodCallHandler
                        }

                        val file = File(filePath)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "File không tồn tại: $filePath", null)
                            return@setMethodCallHandler
                        }

                        val exif = ExifInterface(filePath)

                        // setLatLong() tự động convert sang DMS rational chuẩn EXIF
                        // và ghi cả GPSLatitudeRef / GPSLongitudeRef đúng chuẩn
                        exif.setLatLong(latitude, longitude)

                        // Ghi Altitude (GPSAltitude + GPSAltitudeRef)
                        exif.setAltitude(altitude)

                        // Ghi GPS Timestamp UTC
                        val utcCal = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
                        val hh = utcCal.get(Calendar.HOUR_OF_DAY)
                        val mm = utcCal.get(Calendar.MINUTE)
                        val ss = utcCal.get(Calendar.SECOND)
                        exif.setAttribute(ExifInterface.TAG_GPS_TIMESTAMP, "$hh/1,$mm/1,$ss/1")

                        // Ghi GPS Datestamp theo chuẩn EXIF: YYYY:MM:DD
                        val yyyy = utcCal.get(Calendar.YEAR)
                        val mo = utcCal.get(Calendar.MONTH) + 1
                        val dd = utcCal.get(Calendar.DAY_OF_MONTH)
                        val dateStr = "$yyyy:${mo.toString().padStart(2,'0')}:${dd.toString().padStart(2,'0')}"
                        exif.setAttribute(ExifInterface.TAG_GPS_DATESTAMP, dateStr)

                        // GPSProcessingMethod: ghi đúng nguồn xác định vị trí
                        // "GPS" = từ tín hiệu vệ tinh GPS
                        // "NETWORK" = từ mạng viễn thông (Cell tower) hoặc WiFi
                        exif.setAttribute(ExifInterface.TAG_GPS_PROCESSING_METHOD, provider)

                        exif.saveAttributes() // Ghi tất cả thay đổi vào file
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("EXIF_WRITE_ERROR", "Lỗi ghi GPS EXIF: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
