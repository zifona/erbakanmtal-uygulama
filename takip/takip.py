"""Okul sitesinde yeni haber/duyuru var mı diye bakar, varsa bildirim gönderir.

GitHub Actions bunu her 15 dakikada bir çalıştırır. Görülen içerikler
takip/gorulen.json dosyasında tutulur.

Ortam değişkenleri:
  FIREBASE_SERVICE_ACCOUNT : Firebase hizmet hesabı JSON içeriği (GitHub Secret)
  DENEME_BILDIRIMI=1       : Sadece bir deneme bildirimi gönderir
"""
import json
import os
import re
import sys
from pathlib import Path
from urllib.parse import unquote, urljoin

import requests
from bs4 import BeautifulSoup

SITE = "https://profdrnecmettinerbakanmtal.meb.k12.tr"
OKUL_ADI = "Prof. Dr. Necmettin Erbakan MTAL"
KONU = "okul"  # Uygulamadaki bildirimKonusu ile aynı olmalı
SAYFALAR = [
    SITE + "/",
    SITE + "/icerikler/icerikler/listele_2339195_Haberler",
    SITE + "/icerikler/icerikler/listele_2339196_Duyurular",
]
DURUM_DOSYASI = Path(__file__).with_name("gorulen.json")
ICERIK_DESENI = re.compile(r"/icerikler/[^/?#]+_(\d+)\.html$")
TEK_SEFERDE_EN_FAZLA = 5    # Bir kontrolde gönderilecek en fazla tek tek bildirim
SUPHELI_SAYI = 15           # Bundan fazla "yeni" içerik çıkarsa site değişmiş olabilir
SAKLANACAK = 500

oturum = requests.Session()
oturum.headers["User-Agent"] = (
    "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36"
)


def sayfa_getir(url):
    r = oturum.get(url, timeout=30)
    r.raise_for_status()
    if not r.encoding or r.encoding.lower() == "iso-8859-1":
        r.encoding = r.apparent_encoding
    return r.text


def icerikleri_bul(html, taban):
    """Sayfadaki haber/duyuru bağlantılarını {id: {url, baslik}} olarak döndürür."""
    sonuc = {}
    soup = BeautifulSoup(html, "html.parser")
    for a in soup.find_all("a", href=True):
        url = urljoin(taban, a["href"].strip())
        if not url.startswith(SITE):
            continue
        m = ICERIK_DESENI.search(unquote(url.split("#")[0]))
        if not m:
            continue
        baslik = a.get("title") or a.get_text(" ", strip=True)
        baslik = re.sub(r"\s+", " ", baslik).strip()
        eski = sonuc.get(m.group(1))
        # Aynı içerik birden çok kez geçiyorsa en uzun başlığı tut.
        if not eski or len(baslik) > len(eski["baslik"]):
            sonuc[m.group(1)] = {"url": url, "baslik": baslik}
    return sonuc


def tam_baslik(url, yedek):
    """Ana sayfadaki başlıklar kısaltılmış olabilir; içeriğin kendi sayfasından al."""
    try:
        soup = BeautifulSoup(sayfa_getir(url), "html.parser")
        og = soup.find("meta", property="og:title")
        if og and og.get("content", "").strip():
            return og["content"].strip()
        h1 = soup.find("h1")
        if h1 and h1.get_text(strip=True):
            return h1.get_text(" ", strip=True)
    except Exception as e:  # noqa: BLE001
        print(f"  Başlık alınamadı ({e}), kısa başlık kullanılacak")
    return yedek.rstrip(". …") if yedek else "Yeni içerik yayınlandı"


def fcm_gonder(baslik, metin, url=None):
    bilgi = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "").strip()
    if not bilgi:
        print(f"  [Firebase ayarlı değil, gönderilmedi] {baslik}: {metin}")
        return False
    from google.oauth2 import service_account
    from google.auth.transport.requests import Request

    hesap = json.loads(bilgi)
    kimlik = service_account.Credentials.from_service_account_info(
        hesap, scopes=["https://www.googleapis.com/auth/firebase.messaging"]
    )
    kimlik.refresh(Request())
    mesaj = {
        "message": {
            "topic": KONU,
            "notification": {"title": baslik, "body": metin},
            "data": {"url": url or SITE + "/"},
            "android": {"priority": "high"},
        }
    }
    r = requests.post(
        f"https://fcm.googleapis.com/v1/projects/{hesap['project_id']}/messages:send",
        headers={"Authorization": f"Bearer {kimlik.token}"},
        json=mesaj,
        timeout=30,
    )
    if r.ok:
        print(f"  Bildirim gönderildi: {metin}")
        return True
    print(f"  Bildirim HATASI {r.status_code}: {r.text}")
    return False


def main():
    if os.environ.get("DENEME_BILDIRIMI") == "1":
        ok = fcm_gonder(OKUL_ADI, "Deneme bildirimi: bildirim sistemi çalışıyor.")
        sys.exit(0 if ok else 1)

    bulunan = {}
    for url in SAYFALAR:
        try:
            yeni = icerikleri_bul(sayfa_getir(url), url)
            print(f"{url} -> {len(yeni)} içerik")
            for k, v in yeni.items():
                if k not in bulunan or len(v["baslik"]) > len(bulunan[k]["baslik"]):
                    bulunan[k] = v
        except Exception as e:  # noqa: BLE001
            print(f"{url} okunamadı: {e}")

    if not bulunan:
        print("Hiç içerik bulunamadı (site erişilemiyor olabilir). Durum değiştirilmedi.")
        return

    ilk_calisma = not DURUM_DOSYASI.exists()
    gorulen = set() if ilk_calisma else set(json.loads(DURUM_DOSYASI.read_text())["gorulen"])
    yeniler = sorted((k for k in bulunan if k not in gorulen), key=int)

    if ilk_calisma:
        print(f"İlk çalışma: {len(bulunan)} mevcut içerik kaydedildi, bildirim gönderilmedi.")
    elif not yeniler:
        print("Yeni içerik yok.")
        return
    elif len(yeniler) > SUPHELI_SAYI:
        print(f"{len(yeniler)} yeni içerik çıktı; site yapısı değişmiş olabilir. "
              "Bildirim gönderilmeden kaydedildi.")
    elif len(yeniler) > TEK_SEFERDE_EN_FAZLA:
        fcm_gonder(OKUL_ADI, f"Sitemizde {len(yeniler)} yeni haber ve duyuru yayınlandı.")
    else:
        for k in yeniler:
            b = bulunan[k]
            fcm_gonder(OKUL_ADI, tam_baslik(b["url"], b["baslik"]), b["url"])

    tum = sorted(gorulen | set(bulunan), key=int)[-SAKLANACAK:]
    DURUM_DOSYASI.write_text(json.dumps({"gorulen": tum}, indent=1) + "\n")


if __name__ == "__main__":
    main()
