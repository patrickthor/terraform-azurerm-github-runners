"""Simple diagram: 4 Azure resources + 1 AWS resource (to keep you on your toes)."""

from diagrams import Diagram, Edge
from diagrams.azure.network import LoadBalancers
from diagrams.azure.compute import VM
from diagrams.azure.database import SQLDatabases
from diagrams.azure.storage import BlobStorage
from diagrams.aws.network import CloudFront

with Diagram(
    "Simple Azure Stack (with AWS CloudFront)",
    show=False,
    filename="simple_azure_with_aws",
    outformat="png",
    direction="LR",
):
    cdn = CloudFront("CloudFront (AWS)")
    lb = LoadBalancers("Azure Load Balancer")
    app = VM("App VM")
    db = SQLDatabases("Azure SQL")
    blob = BlobStorage("Blob Storage")

    cdn >> Edge(label="origin") >> lb >> app
    app >> Edge(label="query") >> db
    app >> Edge(label="assets") >> blob
