import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as win;

void main() => runApp(const BanzelApp());

class BanzelApp extends StatelessWidget {
  const BanzelApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'بانزل زه',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF1F6FEB), useMaterial3: true),
        locale: const Locale('fa'),
        builder: (c, w) => Directionality(textDirection: TextDirection.rtl, child: w!),
        home: const Root(),
      );
}

class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  String? url;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) => setState(() {
          url = p.getString('server_url');
          loaded = true;
        }));
  }

  Future<void> save(String v) async {
    var u = v.trim();
    if (!u.startsWith('http')) u = 'https://$u';
    final p = await SharedPreferences.getInstance();
    await p.setString('server_url', u);
    setState(() => url = u);
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (url == null) return SetupPage(onSave: save);
    return Shell(url: url!, onChangeUrl: () => setState(() => url = null));
  }
}

class SetupPage extends StatefulWidget {
  final Future<void> Function(String) onSave;
  const SetupPage({super.key, required this.onSave});
  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final c = TextEditingController();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('بانزل زه', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const Text('آدرس سرور برنامه را وارد کنید (همان آدرسی که در مرورگر باز می‌کنید):'),
                const SizedBox(height: 8),
                TextField(
                  controller: c,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(hintText: 'https://example.ir/banzel/', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: () { if (c.text.trim().isNotEmpty) widget.onSave(c.text); }, child: const Text('ذخیره و ورود')),
              ]),
            ),
          ),
        ),
      );
}

class Shell extends StatelessWidget {
  final String url;
  final VoidCallback onChangeUrl;
  const Shell({super.key, required this.url, required this.onChangeUrl});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Column(children: [
            Container(
              height: 30,
              color: const Color(0xFF16202C),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                const Text('بانزل زه', style: TextStyle(color: Colors.white, fontSize: 13)),
                const Spacer(),
                InkWell(onTap: onChangeUrl, child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.settings, color: Colors.white70, size: 18))),
              ]),
            ),
            Expanded(child: Platform.isWindows ? WinView(url: url) : AndroidView(url: url)),
          ]),
        ),
      );
}

// ---------------- اندروید ----------------
class AndroidView extends StatefulWidget {
  final String url;
  const AndroidView({super.key, required this.url});
  @override
  State<AndroidView> createState() => _AndroidViewState();
}

class _AndroidViewState extends State<AndroidView> {
  late final WebViewController ctrl;
  String? error;

  @override
  void initState() {
    super.initState();
    ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('BanzelPrint', onMessageReceived: (m) async {
        try {
          final j = jsonDecode(m.message) as Map<String, dynamic>;
          final mmToPt = 72 / 25.4;
          final w = (j['w'] as num) * mmToPt, h = (j['h'] as num) * mmToPt, mg = (j['m'] as num) * mmToPt;
          await Printing.layoutPdf(
            name: j['title'] as String? ?? 'فاکتور',
            format: PdfPageFormat(w.toDouble(), h.toDouble(), marginAll: mg.toDouble()),
            onLayout: (f) => Printing.convertHtml(format: f, html: j['html'] as String),
          );
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('چاپ انجام نشد: $e')));
        }
      })
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (e) { if (e.isForMainFrame ?? true) setState(() => error = e.description); },
        onPageStarted: (_) => setState(() => error = null),
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) => error != null
      ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('اتصال به سرور برقرار نشد'), Text(error!, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 12), FilledButton(onPressed: () { setState(() => error = null); ctrl.loadRequest(Uri.parse(widget.url)); }, child: const Text('تلاش دوباره')),
        ])))
      : WebViewWidget(controller: ctrl);
}

// ---------------- ویندوز ----------------
class WinView extends StatefulWidget {
  final String url;
  const WinView({super.key, required this.url});
  @override
  State<WinView> createState() => _WinViewState();
}

class _WinViewState extends State<WinView> {
  final c = win.WebviewController();
  bool ready = false;
  String? error;

  @override
  void initState() {
    super.initState();
    () async {
      try {
        await c.initialize();
        await c.setBackgroundColor(Colors.white);
        await c.loadUrl(widget.url);
        if (mounted) setState(() => ready = true);
      } catch (e) {
        if (mounted) setState(() => error = '$e');
      }
    }();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('خطا در راه‌اندازی WebView2. آن را از سایت مایکروسافت نصب کنید.\n$error', textDirection: TextDirection.ltr)));
    }
    return ready ? win.Webview(c) : const Center(child: CircularProgressIndicator());
  }
}
