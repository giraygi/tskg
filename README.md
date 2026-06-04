# TSKG
* Set `TOKEN` by `export TOKEN=xxxxxxxx` to be able to extract data from matomo. Configure matomo statistics data with further parameters in the file.
* Choose the most frequently used ontologies based on their minimum number of actions in the given dates by `export MIN_ACTIONS=5000`. The default value is 5000.
* Choose the date to extract the most frequently used ontologies by `export DATE=last30`. The notation is based on Matomo API. The default value is last30 .
* Run the application by `docker compose up -d`
* Run the UI of the SPARQL endpoint from: http://localhost:8176/TS
