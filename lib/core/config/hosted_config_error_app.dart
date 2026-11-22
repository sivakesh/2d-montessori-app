import 'package:flutter/material.dart';

import 'hosted_firebase_config.dart';

/// Shown instead of the app when a hosted build can't get a valid Firebase
/// configuration: what happened, and Retry. Standalone (no providers, no
/// Firebase), since nothing else has started.
class HostedConfigErrorApp extends StatelessWidget {
  const HostedConfigErrorApp({super.key, required this.error, required this.onRetry});

  final HostedConfigException error;
  final VoidCallback onRetry;

  static const retryKey = Key('hosted-config-retry');

  /// What the visitor is told for each problem.
  static String messageFor(HostedConfigProblem problem) => switch (problem) {
        HostedConfigProblem.unavailable => "The app couldn't load its settings. Check your internet connection and try again.",
        HostedConfigProblem.invalidResponse => "The app's settings couldn't be read. Please try again. If this keeps happening, contact the school office.",
        HostedConfigProblem.projectMismatch => 'The app has stopped for safety because it is connected to the wrong service. Please contact the school office.',
        HostedConfigProblem.buildMisconfigured => 'This version of the app is not set up correctly. Please contact the school office.',
      };

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _HostedConfigErrorPage(error: error, onRetry: onRetry),
    );
  }
}

class _HostedConfigErrorPage extends StatefulWidget {
  const _HostedConfigErrorPage({required this.error, required this.onRetry});

  final HostedConfigException error;
  final VoidCallback onRetry;

  @override
  State<_HostedConfigErrorPage> createState() => _HostedConfigErrorPageState();
}

class _HostedConfigErrorPageState extends State<_HostedConfigErrorPage> {
  // One retry per error shown: the next attempt replaces this page.
  bool _retrying = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 48),
                const SizedBox(height: 16),
                Text("The app can't start right now", textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(HostedConfigErrorApp.messageFor(widget.error.problem), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(widget.error.detail, key: const Key('hosted-config-detail'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: HostedConfigErrorApp.retryKey,
                  onPressed: _retrying
                      ? null
                      : () {
                          setState(() => _retrying = true);
                          widget.onRetry();
                        },
                  icon: const Icon(Icons.refresh),
                  label: Text(_retrying ? 'Retrying…' : 'Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
