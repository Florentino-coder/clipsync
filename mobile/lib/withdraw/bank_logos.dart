/// Maps bank code → bundled logo asset path (in-app only; no network fetch).
String bankLogoAsset(String bank) {
  final key = bank.trim().toUpperCase();
  const map = {
    'KBANK': 'assets/banks/kbank.png',
    'SCB': 'assets/banks/scb.png',
    'BBL': 'assets/banks/bbl.png',
    'KTB': 'assets/banks/ktb.png',
    'GSB': 'assets/banks/gsb.png',
    'TTB': 'assets/banks/ttb.png',
    'BAY': 'assets/banks/bay.png',
  };
  return map[key] ?? 'assets/banks/generic.png';
}
