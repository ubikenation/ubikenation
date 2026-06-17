import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/app_theme.dart';

/// Embedded Paystack checkout. Loads the authorization URL and watches for the
/// redirect to our callback sentinel; on success it pops `true`.
class PaystackWebView extends StatefulWidget {
  const PaystackWebView({super.key, required this.url, required this.callbackUrl});
  final String url;
  final String callbackUrl;

  @override
  State<PaystackWebView> createState() => _PaystackWebViewState();
}

class _PaystackWebViewState extends State<PaystackWebView> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
          onNavigationRequest: (request) {
            // Paystack redirects here (with ?reference&trxref) after a successful charge.
            if (request.url.startsWith(widget.callbackUrl) || request.url.contains('paystack.co/close')) {
              Navigator.of(context).pop(true);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure Payment'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop(false)),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const LinearProgressIndicator(color: AppTheme.primary),
        ],
      ),
    );
  }
}
