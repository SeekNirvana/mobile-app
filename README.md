# SeekNirvana

SeekNirvana is a Flutter-based mobile application designed to be the companion app for a smart ring, focusing on health and wellness tracking.

## About the App

This app allows users to connect their smart ring and monitor various health metrics. The app provides a user-friendly interface to visualize and track health data over time.

## Features

*   **Home:** A central dashboard providing an overview of your health data.
*   **Scan:** Easily scan for and connect your smart ring.
*   **Vitals:** Track and monitor your vital signs.
*   **Sleep:** Analyze your sleep patterns and quality.
*   **Profile:** Manage your user profile and settings.

## Technology Stack

*   **Flutter:** The UI toolkit for building natively compiled applications for mobile, web, and desktop from a single codebase.
*   **Riverpod:** A reactive state management and dependency injection framework.
*   **GoRouter:** A declarative routing package for Flutter.
*   **fl_chart:** A library to create beautiful charts and graphs.
*   **Permission Handler:** A plugin to manage app permissions.
*   **Shared Preferences:** For storing key-value data on disk.

## Project Structure

The project is organized into the following main directories under `lib/`:

*   `core/`: Contains the core functionalities of the application.
*   `features/`: Each feature of the app is a separate module here.
*   `providers/`: Contains all the Riverpod providers for state management.
*   `services/`: Houses various services used in the app, like data fetching.
*   `shared/`: Contains shared widgets, models, and utilities.
