import _ from "lodash";
import React, { PropTypes } from "react";
import { Panel } from "react-bootstrap";
import ObservationFieldValue from "./observation_field_value";
import ObservationFieldInput from "./observation_field_input";

class ObservationFields extends React.Component {

  constructor( ) {
    super( );
    this.state = { open: false };
  }

  render( ) {
    const { observation, config } = this.props;
    const loggedIn = config && config.currentUser;
    if ( !observation || ( _.isEmpty( observation.ofvs ) && !loggedIn ) ) {
      return ( <span /> );
    }
    // fieldIDs used by projects
    const projectFieldIDs = _.compact( _.flatten( observation.project_observations.map( po => (
      ( po.project.project_observation_fields || [] ).map( pof => (
        pof.observation_field.id ) ) ) ) ) );
    let nonProjectFieldValues = observation.ofvs;
    if ( projectFieldIDs.length > 0 ) {
      // remove any project fields from this presentation
      nonProjectFieldValues = _.filter( observation.ofvs, ofv => ( (
        !_.includes( projectFieldIDs, ofv.field_id )
      ) ) );
    }
    if ( _.isEmpty( nonProjectFieldValues ) && !loggedIn ) { return ( <span /> ); }
    const sortedFieldValues = _.sortBy( nonProjectFieldValues, ofv => (
      `${ofv.value ? "a" : "z"}:${ofv.name}:${ofv.value}`
    ) );
    let addValueLink;
    let addValueInput;
    if ( loggedIn ) {
      addValueLink = (
        <span
          className="add"
          onClick={ ( ) => this.setState( { open: !this.state.open } ) }
        >Add Field</span>
      );
      addValueInput = (
        <Panel collapsible expanded={ this.state.open }>
          <div className="form-group">
            <ObservationFieldInput
              observationField={ this.state.observationField }
              notIDs={ _.uniq( _.map( observation.ofvs, ofv => ofv.observation_field.id ) ) }
              onSubmit={ r => {
                this.props.addObservationFieldValue( r );
              } }
            />
          </div>
        </Panel>
      );
    }
    return (
      <div className="ObservationFields">
        <h4>Observation Fields ({ sortedFieldValues.length }) { addValueLink }</h4>
        { addValueInput }
        { sortedFieldValues.map( ofv => (
          <ObservationFieldValue
            ofv={ ofv }
            key={ `field-value-${ofv.uuid}`}
            { ...this.props }
          />
        ) ) }
      </div>
    );
  }
}

ObservationFields.propTypes = {
  config: PropTypes.object,
  observation: PropTypes.object,
  addObservationFieldValue: PropTypes.func,
  removeObservationFieldValue: PropTypes.func
};

export default ObservationFields;
