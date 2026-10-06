"""Sample diagram: 4 Azure resources + 1 AWS resource."""

from diagrams import Diagram, Edge
from diagrams.azure.web import AppServices
from diagrams.azure.compute import FunctionApps
from diagrams.azure.database import SQLDatabases
from diagrams.azure.security import KeyVaults
from diagrams.aws.storage import SimpleStorageServiceS3

with Diagram(
    "Mixed Cloud Sample",
    show=False,
    filename="mixed_cloud_sample",
    outformat="png",
    direction="LR",
):
    web = AppServices("App Service")
    func = FunctionApps("Function App")
    db = SQLDatabases("SQL Database")
    vault = KeyVaults("Key Vault")
    s3 = SimpleStorageServiceS3("S3 (AWS)")

    web >> func >> db
    vault >> Edge(label="secrets") >> web
    vault >> Edge(label="secrets") >> func
    web >> Edge(label="objects") >> s3
