import 'package:flutter/material.dart';

import 'verse_card.dart';

class VerseScreen extends StatelessWidget {
  const VerseScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('آية اليوم')),
        body: const SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: VerseCard(expanded: true),
        ),
      );
}
