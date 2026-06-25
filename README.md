# Terminology Service Knowledge Graph
This repository intends to identify the most frequently used ontologies from the [TIB Terminology Service](https://github.com/TIBHannover/ols4), download the most recent version of these ontologies and index them along with their previously downloaded versions in Qlever as a Knowledge Graph. 
## Installation
The installation requires an input config file like the example [ontologies.json](./ontologies.json) that contains the id and purl of the ontologies to be indexed. The input config file follows the format of a config file of the Terminology Service and sample config files can be accessed from https://github.com/TIBHannover/ols4/tree/dev/dataload/configs . It is important for the config file to be inclusive and include all possible ontologies that are desired to be queried. Still, it should also be noted that not all the fields in an the config of a particular ontology are important while generating a config file and the mandatory fields of an ontology are "id" and "ontology_purl". After the initial config file generation step, the most frequently used ontologies are identified using a data range and minimum number of actions as they are explained in the installation routine below. Later, if identified ontologies are present in the original config file then they are downloaded. The final product outputs the Terminology Service Knowledge Graph as both a backend service at http://localhost:7001 and a frontend service at http://localhost:8176/ts. As long as the [data](./data)  directory is not deleted, it will become possible to download and simultaneously index newer versions of the same ontology along with its earlier versions. Below you can find the installation routine of the service: 
- Set `TOKEN` by `export TOKEN=xxxxxxxx` to be able to extract data from matomo. Configure matomo statistics data with further parameters in the file.
- Choose the most frequently used ontologies based on their minimum number of actions in the given dates by `export MIN_ACTIONS=5000`. The default value is 5000.
- Choose the date to extract the most frequently used ontologies by `export DATE=last30`. The notation is based on Matomo API. The default value is last30 .
- Run the application by `docker compose up -d`
- Assign super user by `docker compose exec qlever-ui python manage.py shell -c "from django.contrib.auth.models import User; User.objects.create_superuser('admin','admin@admin.com','password')"`
- Run the UI of the SPARQL endpoint from: http://localhost:8176/ts and execute the following query to test `SELECT * WHERE { ?s ?p ?o } LIMIT 10`
- You can test the backend directly with a query like: curl "http://localhost:7001/?query=SELECT+*+WHERE+%7B+?s+?p+?o+%7D+LIMIT+10"


## Querying Multiple Versions of an Ontology
- The following query shows the exact version IRIs of "obi" ontology that are indexed:

```
SELECT DISTINCT ?g WHERE {
  GRAPH ?g { ?s ?p ?o }
  FILTER(CONTAINS(STR(?g), "obi"))
}
```

- A query for the terms present in one version but not the other (delta)

```
PREFIX owl:  <http://www.w3.org/2002/07/owl#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

SELECT ?class ?label WHERE {
  GRAPH <http://purl.obolibrary.org/obo/obi/2026-05-08/obi.owl> {
    ?class a owl:Class ; rdfs:label ?label .
  }
  FILTER NOT EXISTS {
    GRAPH <http://purl.obolibrary.org/obo/obi/2025-01-09/obi.owl> {
      ?class a owl:Class .
    }
  }
}
```
- A query to locate the new classes in the term hierarchy

```
PREFIX obo:  <http://purl.obolibrary.org/obo/>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX owl:  <http://www.w3.org/2002/07/owl#>

SELECT ?new ?newLabel ?parent ?parentLabel WHERE {
  GRAPH <http://purl.obolibrary.org/obo/obi/2026-05-08/obi.owl> {
    ?new rdfs:label ?newLabel ;
         rdfs:subClassOf ?parent .
    ?parent rdfs:label ?parentLabel .
  }
  FILTER NOT EXISTS {
    GRAPH <http://purl.obolibrary.org/obo/obi/2025-01-09/obi.owl> {
      ?new a owl:Class .
    }
  }
  FILTER(STRSTARTS(STR(?new), STR(obo:OBI_)))
}
ORDER BY ?parentLabel
```