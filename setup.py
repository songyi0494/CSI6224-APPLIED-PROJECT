from setuptools import find_packages, setup

setup(
    name="osteoporosis-cdss",
    version="5.1.0",
    package_dir={"": "src"},
    packages=find_packages("src"),
    python_requires=">=3.9",
    install_requires=[
        "fastapi>=0.110", "uvicorn[standard]>=0.29", "pydantic>=2.6", "supabase>=2.4",
        "numpy>=1.26", "pandas>=2.1", "scipy>=1.11", "scikit-learn>=1.4", "joblib>=1.3",
        "matplotlib>=3.8", "shap>=0.45",
    ],
    extras_require={"dev": ["pytest>=8.0", "httpx>=0.27"]},
)
