"""`flutter create` sonrası Android ayarlarını düzenler (GitHub'da otomatik çalışır).

- Uygulama adı ve internet izni (AndroidManifest.xml)
- En düşük Android sürümü (minSdk 23, Firebase için gerekli)
- Play Store için imza ayarı (KEYSTORE_PATH ortam değişkeni varsa)
"""
import re
import sys
from pathlib import Path

UYGULAMA_ADI = "Erbakan MTAL"
MIN_SDK = 23

manifest = Path("android/app/src/main/AndroidManifest.xml")
m = manifest.read_text(encoding="utf-8")
m = re.sub(r'android:label="[^"]*"', f'android:label="{UYGULAMA_ADI}"', m, count=1)
if "android.permission.INTERNET" not in m:
    m = m.replace(
        "<application",
        '<uses-permission android:name="android.permission.INTERNET"/>\n    <application',
        1,
    )
manifest.write_text(m, encoding="utf-8")
print("AndroidManifest.xml düzenlendi")

kts = Path("android/app/build.gradle.kts")
groovy = Path("android/app/build.gradle")

if kts.exists():
    g = kts.read_text(encoding="utf-8")
    g = re.sub(r"minSdk\s*=\s*[\w.]+", f"minSdk = {MIN_SDK}", g, count=1)
    imza = '''
    signingConfigs {
        create("release") {
            val ks = System.getenv("KEYSTORE_PATH")
            if (ks != null) {
                storeFile = file(ks)
                storePassword = System.getenv("KEYSTORE_PASSWORD")
                keyAlias = System.getenv("KEY_ALIAS")
                keyPassword = System.getenv("KEY_PASSWORD")
            }
        }
    }

    buildTypes {'''
    if "signingConfigs {" not in g:
        g = g.replace("\n    buildTypes {", imza, 1)
    g = re.sub(
        r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
        'signingConfig = if (System.getenv("KEYSTORE_PATH") != null) '
        'signingConfigs.getByName("release") else signingConfigs.getByName("debug")',
        g,
        count=1,
    )
    kts.write_text(g, encoding="utf-8")
    print("build.gradle.kts düzenlendi")
elif groovy.exists():
    g = groovy.read_text(encoding="utf-8")
    g = re.sub(r"minSdk(Version)?\s*=?\s*[\w.]+", f"minSdk = {MIN_SDK}", g, count=1)
    imza = '''
    signingConfigs {
        release {
            if (System.getenv("KEYSTORE_PATH") != null) {
                storeFile file(System.getenv("KEYSTORE_PATH"))
                storePassword System.getenv("KEYSTORE_PASSWORD")
                keyAlias System.getenv("KEY_ALIAS")
                keyPassword System.getenv("KEY_PASSWORD")
            }
        }
    }

    buildTypes {'''
    if "signingConfigs {" not in g:
        g = g.replace("\n    buildTypes {", imza, 1)
    g = re.sub(
        r"signingConfig\s*=?\s*signingConfigs\.debug",
        'signingConfig = System.getenv("KEYSTORE_PATH") != null ? '
        "signingConfigs.release : signingConfigs.debug",
        g,
        count=1,
    )
    groovy.write_text(g, encoding="utf-8")
    print("build.gradle düzenlendi")
else:
    sys.exit("Android build.gradle dosyası bulunamadı")
