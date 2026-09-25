# Pocket Ledger

Pocket Ledger is a private, offline personal finance app for macOS. It tracks subscriptions, everyday expenses, income, current balances, and other assets. All records stay on the Mac.

![Pocket Ledger dashboard](Screenshots/Pocket-Ledger-dashboard.png)

## Features

- Home dashboard with current assets, monthly spending, income, net cash flow, and charts
- Subscription due dates, recurring-cost estimates, local Mac notifications, and “Record paid” actions
- Expenses grouped into categories such as food, online shopping, transport, and bills
- Salary, pocket money, freelance income, gifts, and other money received
- Cash, bank, savings, investment, property, and other asset balances
- Automatic balance updates when income or expenses are linked to an account
- Optional four-digit app lock with secure Keychain storage and Touch ID unlock
- Immediate local saving, up to 30 automatic backups, manual backup/restore, and CSV export
- No login, server, analytics, advertisements, or internet connection

## Requirements

- macOS 14 or later
- Xcode command-line tools (only needed to build from source)

## Build the Mac app

Open Terminal in this folder and run:

```sh
chmod +x build-app.sh
./build-app.sh
```

The finished application will be created at `build/Pocket Ledger.app`.

## Run tests

```sh
swift test --disable-sandbox
```

## Local data

The app saves its database and backups inside:

```text
~/Library/Application Support/Pocket Ledger/
```

Backups can be opened, created, restored, and exported from the app’s **Settings & backup** page.

## Privacy

Pocket Ledger has no networking code. It does not use a cloud service, collect analytics, or transmit financial information.
