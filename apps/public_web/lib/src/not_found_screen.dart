import 'package:flutter/material.dart';

import 'seo_head.dart';

/// SRS WEB-15: "Branded 404 with useful links." Also the screen shown
/// for every slug that exists but isn't currently public — a draft,
/// scheduled, in-review or archived page — see [PublicPagesRepository]'s
/// doc comment for why this route can't distinguish "never existed" from
/// "not currently published" (and must not try to).
class NotFoundScreen extends StatefulWidget {
  const NotFoundScreen({super.key});

  @override
  State<NotFoundScreen> createState() => _NotFoundScreenState();
}

class _NotFoundScreenState extends State<NotFoundScreen> {
  @override
  void initState() {
    super.initState();
    SeoHead.apply(title: 'Page not found — 2D Montessori', indexable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Page not found',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                "The page you're looking for doesn't exist or is no longer available.",
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/', (route) => false),
                child: const Text('Go to homepage'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
