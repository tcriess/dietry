import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_config.dart';
import '../app_features.dart';
import '../l10n/app_localizations.dart';

class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key});

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.infoTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // App-Header
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(
                    Icons.restaurant_menu,
                    size: 40,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Dietry',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snap) {
                    final version = snap.data != null
                        ? '${snap.data!.version}+${snap.data!.buildNumber}'
                        : '…';
                    final hash = AppConfig.gitHash;
                    final date = AppConfig.buildDate;
                    final edition = AppConfig.isCloudEdition ? 'Cloud' : 'CE';
                    final buildLine = [
                      edition,
                      if (hash != 'dev') hash,
                      if (date.isNotEmpty) date,
                    ].join(' · ');
                    return Column(
                      children: [
                        Text(
                          l.infoVersion(version),
                          style: const TextStyle(color: Colors.grey),
                        ),
                        if (buildLine.isNotEmpty)
                          Text(
                            buildLine,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                _EditionBadge(),
                const SizedBox(height: 4),
                Text(
                  l.appSubtitle,
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),

          // Impressum
          _SectionHeader(title: l.infoImpressumSection, icon: Icons.info_outline),
          const SizedBox(height: 8),
          _InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.infoTmgNotice,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('Thorsten Rieß'),
                const Text('Radolfzeller Str. 105A'),
                const Text('78467 Konstanz'),
                const SizedBox(height: 8),
                Text(
                  l.infoContact,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(l.infoEmail),
                const SizedBox(height: 8),
                Text(
                  l.infoResponsible,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Datenschutz
          _SectionHeader(title: l.infoPrivacySection, icon: Icons.shield_outlined),
          const SizedBox(height: 8),
          _InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.infoDataStoredTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _BulletPoint(l.infoDataGoogleAccount),
                _BulletPoint(l.infoDataBody),
                _BulletPoint(l.infoDataMeals),
                _BulletPoint(l.infoDataActivities),
                const SizedBox(height: 8),
                Text(
                  l.infoDataStorageText,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  l.infoDataDeletion,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Externe Dienste & APIs
          _SectionHeader(title: l.infoExternalServices, icon: Icons.cloud_outlined),
          const SizedBox(height: 8),

          _ApiCard(
            name: 'Open Food Facts',
            description: l.infoOffDescription,
            license: 'Open Database License (ODbL)',
            url: 'https://world.openfoodfacts.org',
            onTap: () => _launchUrl('https://world.openfoodfacts.org'),
          ),

          const SizedBox(height: 8),

          _ApiCard(
            name: 'USDA FoodData Central',
            description: l.infoUsdaDescription,
            license: 'Public Domain (US Government)',
            url: 'https://fdc.nal.usda.gov',
            onTap: () => _launchUrl('https://fdc.nal.usda.gov'),
          ),

          const SizedBox(height: 8),

          _ApiCard(
            name: l.infoBlsName,
            description: l.infoBlsDescription,
            license: l.infoBlsLicense,
            url: 'https://www.blsdb.de/',
            onTap: () => _launchUrl('https://www.blsdb.de/'),
          ),

          const SizedBox(height: 8),

          _ApiCard(
            name: l.infoNeonName,
            description: l.infoNeonDescription,
            license: l.infoNeonLicense,
            url: 'https://neon.tech',
            onTap: () => _launchUrl('https://neon.tech'),
          ),

          const SizedBox(height: 8),

          _ApiCard(
            name: 'Google OAuth 2.0',
            description: l.infoGoogleDescription,
            license: 'Google Terms of Service',
            url: 'https://developers.google.com/identity',
            onTap: () => _launchUrl('https://developers.google.com/identity'),
          ),

          if (AppFeatures.microNutrients) ...[
            const SizedBox(height: 8),
            _ApiCard(
              name: l.infoNrvName,
              description: l.infoNrvDescription,
              license: l.infoNrvLicense,
              url: 'https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32011R1169',
              onTap: () => _launchUrl(
                  'https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32011R1169'),
            ),
          ],

          const SizedBox(height: 16),

          // Open-Source-Bibliotheken
          _SectionHeader(title: l.infoOpenSource, icon: Icons.code),
          const SizedBox(height: 8),
          _InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.infoOpenSourceText,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 10),
                const _LibraryRow(name: 'Flutter / Dart', license: 'BSD 3-Clause'),
                const _LibraryRow(name: 'fl_chart', license: 'MIT'),
                const _LibraryRow(name: 'dio', license: 'MIT'),
                const _LibraryRow(name: 'postgrest-dart', license: 'MIT'),
                const _LibraryRow(name: 'flutter_secure_storage', license: 'BSD 3-Clause'),
                const _LibraryRow(name: 'shared_preferences', license: 'BSD 3-Clause'),
                const _LibraryRow(name: 'url_launcher', license: 'BSD 3-Clause'),
                const _LibraryRow(name: 'flutter_appauth', license: 'Apache 2.0'),
                const _LibraryRow(name: 'flutter_web_auth_2', license: 'MIT'),
                const _LibraryRow(name: 'health', license: 'MIT'),
                const _LibraryRow(name: 'image_picker', license: 'Apache 2.0'),
                const _LibraryRow(name: 'share_plus', license: 'BSD 3-Clause'),
                const _LibraryRow(name: 'flutter_local_notifications', license: 'BSD 3-Clause'),
                const _LibraryRow(name: 'webview_flutter', license: 'BSD 3-Clause'),
                const _LibraryRow(name: 'sqflite', license: 'MIT'),
                const _LibraryRow(name: 'http', license: 'BSD 3-Clause'),
                const _LibraryRow(name: 'uuid', license: 'MIT'),
                const _LibraryRow(name: 'logger', license: 'MIT'),
                const _LibraryRow(name: 'package_info_plus', license: 'MIT'),
                const _LibraryRow(name: 'intl', license: 'BSD 3-Clause'),
                const _LibraryRow(name: 'dart_jsonwebtoken', license: 'MIT'),
                if (AppConfig.isCloudEdition)
                  const _LibraryRow(name: 'google_mlkit_text_recognition', license: 'MIT'),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Haftungsausschluss
          _SectionHeader(title: l.infoDisclaimerSection, icon: Icons.gavel_outlined),
          const SizedBox(height: 8),
          _InfoCard(
            child: Text(
              l.infoDisclaimerText,
              style: const TextStyle(fontSize: 13),
            ),
          ),

          const SizedBox(height: 32),

          Center(
            child: Text(
              l.infoCopyright,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Widget child;

  const _InfoCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    );
  }
}

class _ApiCard extends StatelessWidget {
  final String name;
  final String description;
  final String license;
  final String url;
  final VoidCallback onTap;

  const _ApiCard({
    required this.name,
    required this.description,
    required this.license,
    required this.url,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.balance, size: 12, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          license,
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.open_in_new, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryRow extends StatelessWidget {
  final String name;
  final String license;

  const _LibraryRow({required this.name, required this.license});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(name, style: const TextStyle(fontSize: 13)),
          ),
          Text(
            license,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _EditionBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isCloud = AppConfig.isCloudEdition;
    final role = AppFeatures.role;

    final String label;
    final Color bg;
    final Color fg;

    if (!isCloud) {
      label = 'Community Edition';
      bg = Colors.grey.shade200;
      fg = Colors.grey.shade700;
    } else {
      switch (role) {
        case 'pro':
          label = 'Cloud Edition · Pro';
          bg = const Color(0xFFFFD700).withValues(alpha: 0.2);
          fg = const Color(0xFF7A6000);
        case 'basic':
          label = 'Cloud Edition · Basic';
          bg = Theme.of(context).colorScheme.primaryContainer;
          fg = Theme.of(context).colorScheme.onPrimaryContainer;
        default:
          label = 'Cloud Edition · Free';
          bg = Colors.teal.shade50;
          fg = Colors.teal.shade700;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fg,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  final String text;

  const _BulletPoint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 13)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
