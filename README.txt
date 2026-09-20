What it does: This script pulls historical USD/INR exchange rates for specific months and converts the realized revenue of completed bookings into USD to show true FX-adjusted growth.

How to run it: Ensure hotel bookings flat.csv is in the same directory, run the Jupyter Notebook, and execute the final cell.

Design decision: I used a unique-month dictionary cache to look up exchange rates instead of pinging the API for every single row, drastically reducing runtime and avoiding API rate limits.

Limitation: The API uses the closing spot rate for the queried date rather than a blended monthly average, which slightly simplifies intra-month volatility.

Non-Obvious Insight: Month-over-month revenue growth in INR creates a false illusion of performance; when adjusted for USD exchange rates, actual global purchasing power growth was significantly flatter, revealing that volume increases barely offset currency depreciation.

AI Usage Note: I used AI to generate the requests loop and date-parsing logic for the Frankfurter API. I had to FIX the AI's initial output because it attempted to call the API for all 12,000 rows. I corrected this by implementing the month-caching logic to minimize API calls and added the try-except error handling fallback to ensure the script doesn't crash on a timeout.