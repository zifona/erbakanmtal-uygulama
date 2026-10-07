import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ---------------------------------------------------------------------------
// OKUL AYARLARI
// ---------------------------------------------------------------------------
const String okulAdi = 'Prof. Dr. Necmettin Erbakan MTAL';
const String kisaAd = 'Erbakan MTAL';
const String siteHost = 'profdrnecmettinerbakanmtal.meb.k12.tr';
const String siteKok = 'https://$siteHost';
const Color anaRenk = Color(0xFF001236); // logodaki lacivert

/// Bildirim konusu. Takip programı da aynı konuya gönderir.
const String bildirimKonusu = 'okul';

class Sekme {
  const Sekme(this.ad, this.ikon, this.url);
  final String ad;
  final IconData ikon;
  final String url;
}

const List<Sekme> sekmeler = [
  Sekme('Ana Sayfa', Icons.home_rounded, '$siteKok/'),
  Sekme('Haberler', Icons.newspaper_rounded,
      '$siteKok/icerikler/icerikler/listele_2339195_Haberler'),
  Sekme('Duyurular', Icons.campaign_rounded,
      '$siteKok/icerikler/icerikler/listele_2339196_Duyurular'),
  Sekme('İletişim', Icons.call_rounded, '$siteKok/tema/iletisim.php'),
];

/// Uygulama içinde açılmayıp telefondaki ilgili uygulamaya gönderilecek dosyalar.
const List<String> disaridaAcilanUzantilar = [
  '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
  '.zip', '.rar', '.odt', '.ods', '.txt', '.apk',
];

// Firebase bilgileri derleme sırasında GitHub Secrets'tan gelir.
const String _fbApiKey = String.fromEnvironment('FIREBASE_API_KEY');
const String _fbAppId = String.fromEnvironment('FIREBASE_APP_ID');
const String _fbSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
const String _fbProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

bool get firebaseAyarli =>
    _fbApiKey.isNotEmpty &&
    _fbAppId.isNotEmpty &&
    _fbSenderId.isNotEmpty &&
    _fbProjectId.isNotEmpty;

bool firebaseCalisiyor = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? bildirimUrl;

  if (firebaseAyarli) {
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: _fbApiKey,
          appId: _fbAppId,
          messagingSenderId: _fbSenderId,
          projectId: _fbProjectId,
        ),
      );
      firebaseCalisiyor = true;
      // Uygulama kapalıyken bildirime dokunulduysa o sayfayı aç.
      final ilkMesaj = await FirebaseMessaging.instance.getInitialMessage();
      bildirimUrl = _guvenliUrl(ilkMesaj?.data['url']);
    } catch (e) {
      debugPrint('Firebase başlatılamadı: $e');
    }
  }

  runApp(OkulUygulamasi(ilkUrl: bildirimUrl));
}

/// Sadece okul sitesine ait adresleri kabul eder.
String? _guvenliUrl(Object? deger) {
  if (deger is! String) return null;
  final uri = Uri.tryParse(deger);
  if (uri == null || uri.host != siteHost) return null;
  return deger;
}

class OkulUygulamasi extends StatelessWidget {
  const OkulUygulamasi({super.key, this.ilkUrl});
  final String? ilkUrl;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kisaAd,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: anaRenk),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: anaRenk,
          foregroundColor: Colors.white,
        ),
      ),
      home: AnaEkran(ilkUrl: ilkUrl),
    );
  }
}

class AnaEkran extends StatefulWidget {
  const AnaEkran({super.key, this.ilkUrl});
  final String? ilkUrl;

  @override
  State<AnaEkran> createState() => _AnaEkranState();
}

class _AnaEkranState extends State<AnaEkran> {
  late final WebViewController _web;
  int _seciliSekme = 0;
  int _ilerleme = 0;
  bool _yukleniyor = true;
  bool _acilisGosteriliyor = true;
  bool _baglantiHatasi = false;
  String _sonUrl = sekmeler.first.url;
  final List<StreamSubscription<RemoteMessage>> _abonelikler = [];

  @override
  void initState() {
    super.initState();
    _sonUrl = widget.ilkUrl ?? sekmeler.first.url;

    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _gezinmeIstegi,
          onPageStarted: (url) {
            setState(() {
              _yukleniyor = true;
              _baglantiHatasi = false;
              _sonUrl = url;
            });
          },
          onProgress: (p) => setState(() => _ilerleme = p),
          onPageFinished: (_) {
            setState(() {
              _yukleniyor = false;
              _acilisGosteriliyor = false;
            });
          },
          onWebResourceError: (hata) {
            if (hata.isForMainFrame == false) return;
            const baglantiHatalari = {
              WebResourceErrorType.hostLookup,
              WebResourceErrorType.connect,
              WebResourceErrorType.timeout,
            };
            if (baglantiHatalari.contains(hata.errorType)) {
              setState(() {
                _baglantiHatasi = true;
                _yukleniyor = false;
                _acilisGosteriliyor = false;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_sonUrl));

    // Site yavaş açılsa bile açılış ekranı en fazla 8 saniye kalsın.
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && _acilisGosteriliyor) {
        setState(() => _acilisGosteriliyor = false);
      }
    });

    _bildirimleriKur();
  }

  Future<void> _bildirimleriKur() async {
    if (!firebaseCalisiyor) return;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission(alert: true, badge: true, sound: true);
      await fm.subscribeToTopic(bildirimKonusu);

      // Uygulama arka plandayken bildirime dokunuldu.
      _abonelikler.add(FirebaseMessaging.onMessageOpenedApp.listen((m) {
        final url = _guvenliUrl(m.data['url']);
        if (url != null) _ac(url);
      }));

      // Uygulama açıkken bildirim geldi: ekranın altında göster.
      _abonelikler.add(FirebaseMessaging.onMessage.listen((m) {
        if (!mounted) return;
        final baslik = m.notification?.body ?? m.notification?.title;
        if (baslik == null) return;
        final url = _guvenliUrl(m.data['url']);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Yeni: $baslik'),
            duration: const Duration(seconds: 8),
            behavior: SnackBarBehavior.floating,
            action: url == null
                ? null
                : SnackBarAction(label: 'AÇ', onPressed: () => _ac(url)),
          ),
        );
      }));
    } catch (e) {
      debugPrint('Bildirim kurulumu hatası: $e');
    }
  }

  @override
  void dispose() {
    for (final a in _abonelikler) {
      a.cancel();
    }
    super.dispose();
  }

  NavigationDecision _gezinmeIstegi(NavigationRequest istek) {
    if (!istek.isMainFrame) return NavigationDecision.navigate;
    final uri = Uri.tryParse(istek.url);
    if (uri == null) return NavigationDecision.prevent;

    // tel:, mailto:, whatsapp: vb. bağlantılar telefonun uygulamasında açılsın.
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      _disaridaAc(uri);
      return NavigationDecision.prevent;
    }

    // Başka siteler tarayıcıda açılsın.
    if (uri.host != siteHost) {
      _disaridaAc(uri);
      return NavigationDecision.prevent;
    }

    // PDF, Word vb. dosyalar telefonun ilgili uygulamasında açılsın.
    final yol = uri.path.toLowerCase();
    if (disaridaAcilanUzantilar.any(yol.endsWith)) {
      _disaridaAc(uri);
      return NavigationDecision.prevent;
    }

    return NavigationDecision.navigate;
  }

  Future<void> _disaridaAc(Uri uri) async {
    try {
      final acildi = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!acildi && mounted) _uyari('Bu bağlantı açılamadı.');
    } catch (_) {
      if (mounted) _uyari('Bu bağlantı açılamadı.');
    }
  }

  void _uyari(String mesaj) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mesaj)));
  }

  void _ac(String url) {
    setState(() => _baglantiHatasi = false);
    _web.loadRequest(Uri.parse(url));
  }

  void _sekmeSec(int i) {
    setState(() => _seciliSekme = i);
    _ac(sekmeler[i].url);
  }

  Future<void> _geriTusu() async {
    if (await _web.canGoBack()) {
      await _web.goBack();
    } else if (_seciliSekme != 0) {
      _sekmeSec(0);
    } else {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _geriTusu();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(kisaAd,
              style: TextStyle(fontWeight: FontWeight.w600)),
          actions: [
            IconButton(
              tooltip: 'Yenile',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _ac(_sonUrl),
            ),
            IconButton(
              tooltip: 'Tarayıcıda aç',
              icon: const Icon(Icons.open_in_browser_rounded),
              onPressed: () => _disaridaAc(Uri.parse(_sonUrl)),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: _yukleniyor
                ? LinearProgressIndicator(
                    value: _ilerleme > 0 && _ilerleme < 100
                        ? _ilerleme / 100
                        : null,
                    minHeight: 3,
                    color: Colors.amber,
                    backgroundColor: anaRenk,
                  )
                : const SizedBox(height: 3),
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _web),
            if (_baglantiHatasi) _BaglantiYok(onTekrar: () => _ac(_sonUrl)),
            if (_acilisGosteriliyor) const _AcilisEkrani(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _seciliSekme,
          onDestinationSelected: _sekmeSec,
          destinations: [
            for (final s in sekmeler)
              NavigationDestination(icon: Icon(s.ikon), label: s.ad),
          ],
        ),
      ),
    );
  }
}

class _AcilisEkrani extends StatelessWidget {
  const _AcilisEkrani();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: anaRenk,
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/logo.png', width: 160, height: 160),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              okulAdi,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 32),
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
                color: Colors.white, strokeWidth: 3),
          ),
        ],
      ),
    );
  }
}

class _BaglantiYok extends StatelessWidget {
  const _BaglantiYok({required this.onTekrar});
  final VoidCallback onTekrar;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 72, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('İnternet bağlantısı yok',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'Bağlantınızı kontrol edip tekrar deneyin.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onTekrar,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tekrar Dene'),
          ),
        ],
      ),
    );
  }
}
