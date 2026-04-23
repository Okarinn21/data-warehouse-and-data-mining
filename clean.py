import pandas as pd

df = pd.read_csv("mock_data.csv")


df = df.dropna(subset=["Quantity",	"UnitPrice", "CustomerID"])
df["Quantity"] = pd.to_numeric(df["Quantity"], errors="coerce")
df["UnitPrice"] = pd.to_numeric(df["UnitPrice"], errors="coerce")

df["Country"] = df["Country"].str.strip()
df = df[df["Country"] == "United Kingdom"]


df.to_csv("cleaned_data_final.csv", index = False)