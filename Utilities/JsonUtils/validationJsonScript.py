# Call from MATLAB as py.validationJsonScript.validate(filename).
# Remember to restart the pyenv for changes to be seen by MATLAB. This
# is done by calling `terminate(pyenv)` or using the loadModule
# script.

import json
from referencing import Registry, Resource
import jsonschema
from pathlib import Path
import resolveFileInputJson as rjson
import os
import sys

schema_folder = rjson.getBattMoDir() / Path("Utilities") / Path("JsonSchemas")
base_uri = "file://./"
verbose = False


def addJsonSchema(registry, jsonSchemaFilename):
    """Add the jsonschema in the registry"""
    schema_filename = schema_folder / jsonSchemaFilename
    if verbose:
        print(schema_filename)
    with open(schema_filename) as schema_file:
        schema = json.load(schema_file)
    resource = Resource.from_contents(schema)
    uri = base_uri + jsonSchemaFilename
    registry = registry.with_resource(uri=uri, resource=resource)
    return registry


def validate(jsonfile):
    # We collect the schema.json files and add them in the resolver
    registry = Registry()
    for dirpath, dirnames, filenames in os.walk(schema_folder):
        for filename in filenames:
            if filename.endswith(".schema.json"):
                registry = addJsonSchema(registry, filename)

    # We validate the battery schema
    schema_filename = schema_folder / "Simulation.schema.json"
    with open(schema_filename) as schema_file:
        mainschema = json.load(schema_file)
    if verbose:
        print("Validate main schema", mainschema)
    v = jsonschema.Draft202012Validator(mainschema, registry=registry)

    # Validate the input jsonfile
    if verbose:
        print("Validate input file", jsonfile)
    jsonstruct = rjson.loadJsonBattmo(jsonfile)
    v.validate(jsonstruct)

    return True


if __name__ == "__main__":
    # Allow for command line call
    validate(sys.argv[1])
