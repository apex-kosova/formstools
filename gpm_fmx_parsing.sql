---------------------------------------------------------
-- Upload XML file (automatic)
-- from the static files uploaded in a specific APEX app 
---------------------------------------------------------
create or replace package APEX_XXXXXX.GPM_FMX_PARSING
as

G_PROJECT_ID NUMBER;
function create_project(
    pname VARCHAR2,
    pdesc VARCHAR2,
    pschema VARCHAR2,
    psec NUMBER)
return number;

function do_all (pname  varchar2,   -- Project name
                 pdesc  varchar2,   -- Project decription
                 pschema varchar2, -- parsing schema
                 psec   number,      -- security group
                 pflow  number )     -- flow id
return number;

END;
/

-- -----------------------------------------------
-- PACKAGE BODY
-- -----------------------------------------------

create or replace package body APEX_XXXXXX.GPM_FMX_PARSING
as

function create_project (pname VARCHAR2,
                         pdesc VARCHAR2,
                         pschema VARCHAR2,
                         psec NUMBER)
return number
as
t_security_group NUMBER;
begin
    G_PROJECT_ID  := wwv_flow_id.next_val;
    t_security_group := APEX_UTIL.FIND_SECURITY_GROUP_ID('DEMO');
    insert into wwv_mig_projects (
        id, 
        migration_name, 
        description, 
        migration_type, 
        database_schema, 
        security_group_id) 
    values (G_PROJECT_ID, 
            pname,
            pdesc,
            'forms', 
            pschema,
            psec) ;
            

    commit;
    insert into demo.log(msg) values('fin create project');
    commit;
    return G_PROJECT_ID;
exception
when others then raise;
end create_project;

-- -----------------------------------------------
-- Load files
-- -----------------------------------------------
function load_file(pid NUMBER,
                   psec NUMBER)
return number
as
    l_file_name varchar2(255);
    t_project_id NUMBER;
    t_security_group NUMBER;
BEGIN
    for c1 in (select * 
                from   WWV_FLOW_STATIC_FILES
                where  flow_id  = 152 and
                mime_type = 'text/xml')
        loop   
            l_file_name := c1.file_name;
            insert into wwv_mig_forms(
                PROJECT_ID,
                SECURITY_GROUP_ID,
                FILE_NAME,
                FILE_MIME_TYPE,
                FILE_CONTENT)
            values(
                pid,
                psec,   --1203354173872045,
                c1.file_name,
                c1.mime_type,
                c1.file_content
            );           
     end loop;
     insert into demo.log(msg) values('fin load files');
    commit;
    return 0;
END;

------------------------------------------
-- Parse XML data into form Table (XMLDOM)
------------------------------------------

function parse_file (pfid number)
return number as

    l_charset   varchar2(255);
    l_file_name varchar2(255);
    l_clob CLOB;
begin

for c1 in (select *
               from   wwv_mig_forms
               where  id = pfid
    ) loop
    --l_charset   := coalesce(c1.file_char_set, 
    --sys.owa_util.get_cgi_env('REQUEST_IANA_CHARSET'), 'utf-8');
    l_charset := 'UTF-8';
    l_file_name := c1.file_name;

    sys.dbms_lob.createTemporary(l_clob, false);
   --dbms_output.put_line('clob');
    l_clob := wwv_flow_utilities.blob_to_clob (
                p_blob    => c1.file_content,
                p_charset => l_charset);
    update wwv_mig_forms
       set xml_content = XMLTYPE(l_clob)
       where id = pfid;
    sys.dbms_lob.freetemporary(l_clob);

    commit;
    end loop;
    insert into demo.log(msg,ldate) values('fin parse xml',sysdate);
    commit;
    return 0;
    exception
        when others then
            delete wwv_mig_forms where id = pfid;
            commit;
            wwv_flow_error.raise_internal_error (
              p_error_code => wwv_flow_lang.system_message('F4400.XML_PROCESSING_ERROR', wwv_flow_escape.html(l_file_name) ));
end;

-------------------------------------------------
-- Creates all nodes
-------------------------------------------------

function create_nodes(pid NUMBER,
                     pfid NUMBER,
                     psec NUMBER) 
return number
as

    l_charset   varchar2(255);
    l_file_name varchar2(255);
    t_project_id NUMBER;
 
BEGIN
    l_file_name := pfid;   -- instead file_name. Temporary
    if (wwv_mig_frm_load_xml.is_valid_forms_xml(
                p_file_id => pfid,
                p_project_id => pid,
                p_security_group_id => psec)) then 
        begin
            wwv_mig_frm_load_xml.load_all_nodes (
                p_file_id => pfid);
        exception
            when others then
                delete wwv_mig_forms where id = pfid;
                commit;
                wwv_flow_error.raise_internal_error ( p_error_code => wwv_flow_lang.system_message('F4400.XML_PARSING_ERROR', wwv_flow_escape.html(l_file_name)) );
        end;
    else
        delete wwv_mig_forms where id = pfid;
        commit;
        apex_application.g_unrecoverable_error := true;
        wwv_flow_error.raise_internal_error ( p_error_code => wwv_flow_lang.system_message('F4400.XML_PARSING_ERROR', wwv_flow_escape.html(l_file_name)) );
    end if;
    
    insert into demo.log(msg) values('fin load nodes');
    commit;
    return 0;
END;
-- -------------------------------
-- Load revision
---------------------------------
function load_revision (pfid NUMBER)
return number as
-- Populate blocks
begin 
    wwv_mig_frm_utilities.load_frm_revision_tables (
          p_file_id => pfid);
    insert into demo.log(msg) values('fin Revision: '||pfid);
    commit;
    return 0;
    
end load_revision;

-- -------------------------------
-- set component applicability
---------------------------------
function set_applicability(pid NUMBER,
                          psec NUMBER)
return number as

begin
    for c1 in (select component
               from   wwv_mig_project_components
               where  project_id = pid
               and    security_group_id = psec
    ) loop
        if c1.component is not null then
            -- 
            -- Use existing project-level component defaults from wwv_mig_project_components
            -- and apply the default settings to new uploaded files
            --
            wwv_mig_frm_utilities.set_component_applicability(
                                p_component_name => c1.component,
                                p_project_id => pid,
                                p_security_group_id => psec);
        else
            --
            -- Set project-level component defaults, where none exist already in 
            -- wwv_mig_project_components for current migration project
            --
            wwv_mig_frm_utilities.set_component_defaults(
                                p_project_id => pid,
                                p_security_group_id => psec);
        end if;
    end loop;
    insert into demo.log(msg) values('fin set applicability');
    commit;
    return 0;
end set_applicability;

--------------------------------
-- Set trigger applicability
--------------------------------
function set_trigger_applicability( pid NUMBER,
                                psec NUMBER)
return number as

begin
    for c1 in (select trigger_name
               from wwv_mig_project_triggers
               where project_id = pid
               and security_group_id = psec
    ) loop
        if (c1.trigger_name is not null) then
            --
            -- Use existing project-level trigger defaults from wwv_mig_project_triggers
            -- and apply the default settings to new uploaded files
            --
            -- Set Form-Level Triggers across Migration Project
            wwv_mig_frm_utilities.set_formtrig_applicability(
                                p_project_id => pid,
                                p_security_group_id => psec);
            -- Set Block-Level Triggers across Migration Project
            wwv_mig_frm_utilities.set_blktrig_applicability(
                                p_project_id => pid,
                                p_security_group_id => psec);
            -- Set Item-Level Triggers across Migration Project
            wwv_mig_frm_utilities.set_itemtrig_applicability(
                                p_project_id => pid,
                                p_security_group_id => psec);
        else
            --
            -- Set project-level trigger defaults, where none exist already in 
            -- wwv_mig_project_triggers for current migration project
            --
            wwv_mig_frm_utilities.set_trigger_defaults(
                                p_project_id => pid,
                                p_security_group_id => psec);
        end if;
    end loop;
    insert into demo.log(msg) values('fin trigger applicability');
    commit;
    return 0;
end set_trigger_applicability;



------------------------------------------
-- Process Enhanced query
------------------------------------------

function process_enhanced (pid NUMBER, 
                           psec NUMBER, 
                           pschema VARCHAR2)
return number
as
    l_block_id          number;
    l_enhanced_query    varchar2(32676);
    l_original_query    varchar2(32676);
    l_status            varchar2(4)      := null;
    l_block_name        varchar2(255);
    l_block_source      varchar(32676);
begin

    for c1 in (select b.id block_id,
                      b.name block_name,
                      querydatasourcename block_source
               from   wwv_mig_forms p, 
                      wwv_mig_frm_modules m, 
                      wwv_mig_frm_formmodules f, 
                      wwv_mig_frm_blocks b 
               where  p.id = m.file_id
               and    m.id = f.module_id
               and    f.id = b.formmodule_id
               and    p.project_id = pid
    ) LOOP
        l_block_id       := c1.block_id;
        l_block_name     := c1.block_name;
        l_block_source   := c1.block_source;
        l_status         := null;
        l_original_query := 'select '||chr(10);
    
        if (wwv_mig_frm_utilities.get_block_mapping(
                  p_project_id => pid,
                  p_security_group_id => psec,
                  p_block_id => c1.block_id,
                  p_schema => pschema)  not in ('MASTERDETAIL','BLANK')) then

            if (l_block_source is not null) then 
                for c2 in (select i.id, 
                                  nvl(i.columnname,i.name) column_name,
                                  i.id block_item_id,
                                  i.databaseitem
                           from   wwv_mig_forms p, 
                                  wwv_mig_frm_modules m, 
                                  wwv_mig_frm_formmodules f, 
                                  wwv_mig_frm_blocks b, 
                                  wwv_mig_frm_blk_items i
                           where  p.id = m.file_id
                           and    m.id = f.module_id
                           and    f.id = b.formmodule_id
                           and    b.id = i.block_id
                           and    ((upper(i.databaseitem) = 'TRUE' and i.itemtype <> 'Push Button') or 
                (i.databaseitem is null and (i.itemtype is null or i.itemtype <> 'Push Button')))
                           and    p.project_id = pid
                           and    b.id = l_block_id
                ) LOOP
                    l_original_query := l_original_query || l_status ||'    "'||trim(l_block_name)||'"."'|| trim(c2.column_name) || '"'; 
                    l_status := ','||chr(10);
                END LOOP;
                -- code to check the Table name existing in in the schema
           if wwv_flow_builder.is_valid_table_or_view(pschema, trim(l_block_source)) = 'U' then 
                      l_block_source := upper(l_block_source);
           end if;
           -- end of the code --        

                l_original_query := l_original_query || chr(10) || ' from "' || trim(l_block_source) ||'" "'|| trim(l_block_name) || '"';

                l_enhanced_query := wwv_mig_frm_utilities.trigger_parse_block_sql(pid, l_block_id, pschema);
           
                UPDATE wwv_mig_frm_blocks 
                SET    original_query = l_original_query, 
                       enhanced_query = l_enhanced_query, 
                       use_query = decode(l_enhanced_query,null,'ORIGINAL','ENHANCED'),
                       complete = decode(l_enhanced_query,null,'N','Y'),
                       notes = decode(l_enhanced_query,null,null,wwv_flow_lang.system_message('F4400_ENHANCED_QRY_NOTE'))
                WHERE  id = l_block_id;

                -- Set COMPLETE to 'Y' for block and associated items using Enhanced Query
                if (l_enhanced_query is not null) then
                    -- Fix for bug 7630444 - update only POST-QUERY trigger
                    --UPDATE wwv_mig_frm_blk_triggers
                    --SET    complete = 'Y'
                    --WHERE  block_id = l_block_id;

                    UPDATE wwv_mig_frm_blk_triggers
                    SET    notes = wwv_flow_lang.system_message('F4400_ENHANCED_QRY_TRIG_NOTE'),
                           complete = 'Y'
                    WHERE  block_id = l_block_id
                    AND    name = 'POST-QUERY';
                    --AND    complete = 'Y';

                    FOR c3 IN (select i.id item_id
                               from   wwv_mig_forms p, wwv_mig_frm_modules m, 
                                      wwv_mig_frm_formmodules f, wwv_mig_frm_rev_formmodules rf, 
                                      wwv_mig_frm_blocks b, wwv_mig_frm_rev_blocks rb, 
                                      wwv_mig_frm_blk_items i, wwv_mig_frm_rev_blk_items ri
                               where  p.id = m.file_id
                               and    m.id = f.module_id
                               and    f.id = b.formmodule_id
                               and    f.id = rf.formmodule_id
                               and    b.id = rb.block_id
                               and    b.id = i.block_id
                               and    b.id = l_block_id
                               and    i.id = ri.item_id
                    ) LOOP
        
                        UPDATE wwv_mig_frm_blk_items
                        SET    complete = 'Y'
                        WHERE  id = c3.item_id;
            
                        -- Fix for bug 7630444 - Only POST-QUERY block trigger should be updated now
                        --UPDATE wwv_mig_frm_blk_item_triggers
                        --SET    complete = 'Y'
                        --WHERE  item_id = c3.item_id;
        
                   END LOOP;
                END IF;

                commit;
            end if;
        
        elsif (wwv_mig_frm_utilities.get_block_mapping(
                      p_project_id => pid,
                      p_security_group_id => psec,
                      p_block_id => c1.block_id,
                      p_schema => pschema) = 'BLANK' AND c1.block_source is not null) then

            UPDATE wwv_mig_frm_blocks 
                SET    notes = wwv_flow_lang.system_message('F4400_UNKNOWN_DBSRC_NOTE')
                WHERE  id = l_block_id;

        END IF;    
end loop;
insert into demo.log(msg) values('fin Enhanced query');
    commit;
return 0;
end process_enhanced;

-----------------------------------
-- Convert Post-query to LOV
-----------------------------------
function convert_postquery(pid NUMBER)
return number
as
    l_block_id       number;
begin

  for c1 in ( 
       select b.id block_id
       from   wwv_mig_forms p, 
              wwv_mig_frm_modules m, 
              wwv_mig_frm_formmodules f, 
              wwv_mig_frm_blocks b 
       where  p.id = m.file_id
       and    m.id = f.module_id
       and    f.id = b.formmodule_id
       and    p.project_id = pid
      )
  loop

    l_block_id     := c1.block_id;
    wwv_mig_frm_utilities.trigger_query_to_lov(pid,l_block_id);
    commit;
  end loop;
  insert into demo.log(msg) values('fin post query');
    commit;
  return 0;
end ;

---------------------------------
-- Exclude blocks Without Database
---------------------------------

function exclude_blocks(pid NUMBER,
                        psec NUMBER)
return number
as
begin
  FOR c1 in (SELECT id
                FROM wwv_mig_forms
                WHERE project_id  = pid
                AND security_group_id = psec
  ) LOOP
      wwv_mig_frm_utilities.set_block_inclusion (
        p_file_id => c1.id,
        p_project_id => pid,
        p_security_group_id => psec);
  END LOOP;
    insert into demo.log(msg) values('fin Blocks without db');
    commit;
    return 0;
end exclude_blocks;

-- ------------------------------------
-- do for each form
-- ------------------------------------
function do_form(pid  number,
                 psec number)
return number
as
    CURSOR C1 is 
      SELECT id 
      from wwv_mig_forms
      where file_char_set IS NULL and 
      PROJECT_id = pid;
    l_c1   C1%ROWTYPE; 
    cr NUMBER;
begin
    for l_C1 in C1 loop        -- for each fmb
    
        -- Parse XML
        cr := parse_file (l_C1.id);
        
        -- create nodes
        cr := create_nodes( 
                pid => pid,
                pfid => l_C1.id,
                psec => psec);
                            
        -- Create Blocks
        cr := load_revision (pfid => l_C1.id);  
        
    end loop;
    return 0;
end do_form;

-- ------------------------------------
-- MAIN entry point
-- ------------------------------------

function do_all (pname  varchar2,   -- Project name
                 pdesc  varchar2,   -- Project decription
                 pschema varchar2, -- parsing schema
                 psec   number,     -- security group
                 pflow number)      -- flow id      
return number
as
    t_project_id NUMBER;
    cr NUMBER;
begin
    -- creates a new project
    t_project_id := create_project (
                        pname   => pname,
                        pdesc   => pdesc,
                        pschema => pschema,
                        psec    => psec);
    
    -- load files from static
    cr := load_file(
                pid  => t_project_id,
                psec => psec);
                   
    -- do fmb actions
    cr := do_form(pid => t_project_id,
                  psec => psec);
    
    -- set component applicability
    cr := set_applicability(
                pid => t_project_id,
                psec => psec);
                                
    -- set trigger applicability
    cr := set_trigger_applicability( 
                pid => t_project_id,
                psec => psec);
    
    -- process enhanced
    cr := process_enhanced (
                pid => t_project_id, 
                psec => psec, 
                pschema => pschema);
                           
    -- Convert post-query
    cr := convert_postquery(pid => t_project_id);
    
    -- Exclude Blocks without database
    cr := exclude_blocks(
            pid => t_project_id,
            psec => psec);
    
    return 0;
end do_all;

END GPM_FMX_PARSING;
/


------------------------------------

---- Tables pour fichiers statiques
--------------------------------------


WWV_FLOW_STATIC_FILES

flow_id
file_name
file_content (blob)



Create une table LOG into the PARSING_SCHEMA
Grant all on LOG to APEX_XXXXXX
Create package under SYS

grant execute on apex_XXXXXX.GPM_FMX_PARSING to PARSING_SCHEMA;

----------------------------
Forms Module (_fmb.XML)	FMB			
2	Oracle Report (.XML)	RPT			
3	PL/SQL Library (.PLD)	PLD			
4	Forms Menu (_mmb.XML)	MMB			
5	Object Library (_olb.XML)	OLB

---------------------------------
Bouton
----------------------------

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

