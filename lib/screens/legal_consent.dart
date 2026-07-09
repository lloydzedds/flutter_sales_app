import 'package:flutter/material.dart';

enum LegalDocumentKind { termsAndConditions, privacyPolicy, termsOfService }

class LegalDocument {
  const LegalDocument({
    required this.title,
    required this.updatedLabel,
    required this.sections,
  });

  final String title;
  final String updatedLabel;
  final List<LegalSection> sections;
}

class LegalSection {
  const LegalSection({required this.heading, required this.body});

  final String heading;
  final String body;
}

const _legalUpdatedLabel = 'Last updated: July 9, 2026';

LegalDocument _documentFor(LegalDocumentKind kind) {
  switch (kind) {
    case LegalDocumentKind.termsAndConditions:
      return const LegalDocument(
        title: 'Terms and Conditions',
        updatedLabel: _legalUpdatedLabel,
        sections: [
          LegalSection(
            heading: 'Using Sale Buddy',
            body:
                'Sale Buddy helps you record products, inventory, customers, sales, bills, returns, and backups for your store. You are responsible for checking that the records you enter are accurate.',
          ),
          LegalSection(
            heading: 'Your Responsibility',
            body:
                'You agree to use the app lawfully and to keep your device, Google account, and backup files secure. Sale Buddy should not be used to store illegal, harmful, or unauthorized information.',
          ),
          LegalSection(
            heading: 'Backups and Records',
            body:
                'Local data stays on this device. If you sign in with Google, Sale Buddy can save and restore a backup file in your Google Drive app data. You should keep your own recovery copies for important business records.',
          ),
          LegalSection(
            heading: 'Availability',
            body:
                'The app is provided as a business helper. Features may change over time, and cloud features depend on Google services, your account access, and network availability.',
          ),
        ],
      );
    case LegalDocumentKind.privacyPolicy:
      return const LegalDocument(
        title: 'Privacy Policy',
        updatedLabel: _legalUpdatedLabel,
        sections: [
          LegalSection(
            heading: 'Data You Enter',
            body:
                'Sale Buddy stores the products, customers, sales, returns, store details, and settings that you enter into the app.',
          ),
          LegalSection(
            heading: 'Google Account Data',
            body:
                'When you sign in with Google, Sale Buddy uses your Google account to keep data separate per account and to save or restore backups from the Google Drive app data folder. The app requests only the access needed for its own app backup data.',
          ),
          LegalSection(
            heading: 'Sharing and Exports',
            body:
                'The app shares data only when you choose actions such as exporting CSV or PDF files, sharing bills, sharing backups, or saving files to device storage.',
          ),
          LegalSection(
            heading: 'Deleting Data',
            body:
                'You can delete local data by clearing app data or uninstalling the app. You can delete the cloud backup from Accounts and Backup > Manage My Cloud Data.',
          ),
          LegalSection(
            heading: 'No Sale of Data',
            body:
                'Sale Buddy does not sell the business data you enter. Google services may process data according to the Google policies shown during Google sign-in.',
          ),
        ],
      );
    case LegalDocumentKind.termsOfService:
      return const LegalDocument(
        title: 'Terms of Service',
        updatedLabel: _legalUpdatedLabel,
        sections: [
          LegalSection(
            heading: 'Account Choices',
            body:
                'You can use Sale Buddy locally without an account, or sign in with Google to keep account data separate and use Google Drive app-data backups.',
          ),
          LegalSection(
            heading: 'Google Services',
            body:
                'If you choose Google sign-in or Google Drive backup, Google account and Google API terms also apply to that sign-in and authorization flow.',
          ),
          LegalSection(
            heading: 'Business Decisions',
            body:
                'Reports, profit calculations, stock values, and invoices are based on the information you enter. You should review important figures before using them for business, tax, or accounting decisions.',
          ),
          LegalSection(
            heading: 'Changes',
            body:
                'Sale Buddy may update features, settings, and these terms as the application improves. If the terms change, the app can ask you to accept the latest version before continuing.',
          ),
        ],
      );
  }
}

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.kind});

  final LegalDocumentKind kind;

  @override
  Widget build(BuildContext context) {
    final document = _documentFor(kind);

    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            Text(
              document.updatedLabel,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            for (final section in document.sections) ...[
              Text(
                section.heading,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(section.body),
              const SizedBox(height: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class LegalConsentCard extends StatelessWidget {
  const LegalConsentCard({
    super.key,
    required this.accepted,
    required this.onChanged,
  });

  final bool accepted;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: accepted,
              onChanged: (value) => onChanged(value ?? false),
              title: const Text(
                'I accept Sale Buddy legal terms before continuing.',
              ),
              subtitle: const Text(
                'Please review these documents before signing in or using local mode.',
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _LegalLinkButton(
                  label: 'Terms and Conditions',
                  kind: LegalDocumentKind.termsAndConditions,
                ),
                _LegalLinkButton(
                  label: 'Privacy Policy',
                  kind: LegalDocumentKind.privacyPolicy,
                ),
                _LegalLinkButton(
                  label: 'Terms of Service',
                  kind: LegalDocumentKind.termsOfService,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalLinkButton extends StatelessWidget {
  const _LegalLinkButton({required this.label, required this.kind});

  final String label;
  final LegalDocumentKind kind;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => LegalDocumentScreen(kind: kind)),
        );
      },
      child: Text(label),
    );
  }
}

Future<bool> showLegalConsentSheet(BuildContext context) async {
  var accepted = false;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Review and Accept',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Accept Sale Buddy terms before using Google sign-in.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  LegalConsentCard(
                    accepted: accepted,
                    onChanged: (value) {
                      setSheetState(() {
                        accepted = value;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: accepted
                        ? () => Navigator.of(sheetContext).pop(true)
                        : null,
                    child: const Text('Accept and Continue'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  return result == true;
}
