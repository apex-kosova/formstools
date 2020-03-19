# formstools
Forms Migration Tools within Oracle APEX

goal: be able to upload multiple FMX file in one shot in a Forms Migration Project in APEX console.
Currently, it's only possible to load one file at a time.

CAUTION: No warrantly !
Prerequisites: Access to SYS account.

Create a table named LOG into the PARSING_SCHEMA underlying the workspace (ie: DEMO)
Grant all on LOG to APEX_XXXXXX

adapt the GPM_FMX_PARSING.sql file by modifying the exact value of APEX schema (replace all APEX_XXXXXX strings)
Create package GPM_FMX_PARSING under SYS

grant execute on apex_XXXXXX.GPM_FMX_PARSING to PARSING_SCHEMA;

Create a new app
  Create a new page
    Create a new static Region
      Create a Button
        Create a dynamic Action with PL/SQL action like:
        
         declare
            tsec number;
            cr number;
        begin
            tsec := APEX_UTIL.FIND_SECURITY_GROUP_ID('DEMO');
            cr := apex_XXXXXX.GPM_FMX_PARSING.do_all(
              pname => 'DEMOMIG',
              pdesc => 'Demo Forms Migration',
              pschema => 'DEMO',
              psec => tsec,
              pflow => v('APP_ID');
            );
        end;
 
 Put all the fmx together in a zip file.
 Upload the zip file as a satic file (in shared components)
 Run Application
 Press Button !
 Check the new Migration projet in the Builder Home Page.

Source: Code inside the internal flow 4400.
I just put some pieces of existing code and add a loop.
