from chapkit import BaseConfig, ArtifactHierarchy
from chapkit.api import MLServiceBuilder, MLServiceInfo
from chapkit.api.service_builder import ModelMetadata, PeriodType, AssessedStatus
from chapkit.ml import ShellModelRunner
from pydantic import Field


class EwarsConfig(BaseConfig):
    prediction_periods: int = Field(
        default=3,
        description="Number of periods to predict into the future",
    )
    n_lags: int = Field(
        default=3,
        description="Number of lags to include in the model",
    )
    precision: float = Field(
        default=0.01,
        description="Prior on the precision of fixed effects. Works as regularization",
    )
    additional_continuous_covariates: list[str] = Field(
        default_factory=list,
        description="List of continuous covariate names to include (e.g. rainfall, mean_temperature)",
    )


runner = ShellModelRunner(
    train_command="Rscript scripts/train.R --data {data_file}",
    predict_command="Rscript scripts/predict.R --historic {historic_file} --future {future_file} --output {output_file}",
)

info = MLServiceInfo(
    id="ewars-template",
    display_name="CHAP-EWARS Model",
    description=(
        "Modified version of the World Health Organization (WHO) EWARS model. "
        "EWARS is a Bayesian hierarchical model implemented with the INLA library."
    ),
    model_metadata=ModelMetadata(
        author="CHAP team",
        author_assessed_status=AssessedStatus.orange,
        organization="HISP Centre, University of Oslo",
        organization_logo_url="https://landportal.org/sites/default/files/2024-03/university_of_oslo_logo.png",
        contact_email="knut.rand@dhis2.org",
        citation_info=(
            'Climate Health Analytics Platform. 2025. "CHAP-EWARS model". '
            "HISP Centre, University of Oslo. "
            "https://dhis2-chap.github.io/chap-core/external_models/overview_of_supported_models.html"
        ),
    ),
    period_type=PeriodType.monthly,
    allow_free_additional_continuous_covariates=True,
    required_covariates=["population"],
)

hierarchy = ArtifactHierarchy(name="ewars")

builder = MLServiceBuilder(
    info=info,
    config_schema=EwarsConfig,
    hierarchy=hierarchy,
    runner=runner,
)
app = builder.build()
