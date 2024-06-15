from random import random

from pyspark.context import SparkContext
from pyspark.sql.session import SparkSession


sc = SparkContext()
spark = SparkSession(sc)
text_file = spark.read.text("s3a://S3_BUCKET/example.txt")
print(f"Number of lines {text_file.count()}")