import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'app.dart';
Future<void> main() async {
 WidgetsFlutterBinding.ensureInitialized();
 await Hive.initFlutter();
 await Hive.openBox('preferences');
 const secure=FlutterSecureStorage();
 var encoded=await secure.read(key:'scan_box_key');
 if(encoded==null){final random=Random.secure(); encoded=base64UrlEncode(List<int>.generate(32,(_)=>random.nextInt(256))); await secure.write(key:'scan_box_key',value:encoded);}
 await Hive.openBox('scans',encryptionCipher:HiveAesCipher(base64Url.decode(base64Url.normalize(encoded))));
 runApp(const ProviderScope(child:SkinAiApp()));
}
