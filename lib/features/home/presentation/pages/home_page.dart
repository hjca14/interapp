import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('InterApp'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),

            const Icon(
              Icons.home_rounded,
              size: 72,
            ),

            const SizedBox(height: 12),

            const Center(
              child: Text(
                'Casa',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 24),

            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.circle,
                  color: Colors.green,
                  size: 14,
                ),
                SizedBox(width: 8),
                Text(
                  'Online',
                  style: TextStyle(fontSize: 18),
                ),
              ],
            ),

            const SizedBox(height: 32),

            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Firmware',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text('v0.0.1'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.call),
                    label: const Text('Discar'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Abrir'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            const Text(
              'Últimos eventos',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),

            const SizedBox(height: 12),

            const ListTile(
              leading: Icon(Icons.check_circle_outline),
              title: Text('Inicializado'),
            ),

            const ListTile(
              leading: Icon(Icons.wifi),
              title: Text('Dispositivo conectado'),
            ),
          ],
        ),
      ),
    );
  }
}
