import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/notification_service.dart';
import '../widgets/common.dart';

class NotificationSettingsPage extends StatelessWidget {
  final AppState state;
  final NotificationService service;
  const NotificationSettingsPage(this.state, this.service, {super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([state, service]),
    builder: (context, _) => ContentPage(
      title: 'Notifications',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          const SectionTitle(
            'Prayer reminders',
            subtitle: 'A reminder when each prayer begins at your centre',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Remind me at prayer begins time'),
            value: service.prayerRemindersEnabled,
            onChanged: service.supported && !service.busy
                ? service.setPrayerRemindersEnabled
                : null,
          ),
          Text(
            'Times follow ${state.organisation.timeZone}. The next seven days '
            'are refreshed when you open the app. Your phone may delay a '
            'reminder to save battery.',
          ),
          if (!service.supported)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Prayer reminders are available in the Android and iPhone app.',
              ),
            ),
          if (service.prayerRemindersEnabled) ...[
            const SizedBox(height: 12),
            Text(
              service.scheduledPrayerCount == 0
                  ? 'No upcoming published times are available to schedule yet.'
                  : '${service.scheduledPrayerCount} upcoming prayer reminders.',
            ),
            TextButton.icon(
              onPressed: service.busy
                  ? null
                  : () async {
                      await state.refresh();
                      await service.refreshPrayerSchedule(state.prayers);
                      await service.setPrayerRemindersEnabled(true);
                    },
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh prayer reminders'),
            ),
          ],
          const SectionTitle(
            'Account updates',
            subtitle: 'New tasks and learning updates for your account',
          ),
          if (!service.pushAvailable)
            const Text(
              'Account notifications are not available in this preview. '
              'You can still check updates inside your account.',
            )
          else if (!service.accountReady)
            const Text(
              'Sign in with an active account to enable account notifications.',
            )
          else ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Notify this phone'),
              subtitle: Text(
                service.pushRegistered
                    ? 'Connected to your account'
                    : service.pushOptedIn
                    ? 'Reconnect to finish setting up notifications'
                    : 'Off for your account on this phone',
              ),
              value: service.pushOptedIn,
              onChanged: service.busy ? null : service.setPushEnabled,
            ),
            if (service.pushOptedIn && !service.pushRegistered)
              TextButton.icon(
                onPressed: service.busy
                    ? null
                    : () => service.setPushEnabled(true),
                icon: const Icon(Icons.refresh),
                label: const Text('Reconnect account notifications'),
              ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Account alerts show a general message on your lock screen. '
            'Open the app to read details after signing in. Reading an update '
            'does not complete its task.',
          ),
          if (service.busy)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: LinearProgressIndicator(),
            ),
          if (service.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  service.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
