def text: type == "string" and length > 0 and (test("[[:cntrl:]]") | not);
def nullable_text: . == null or text;
def nullable_content: . == null or (type == "string" and (test("[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f\\x7f]") | not));
def nullable_array: . == null or type == "array";
def provenance_entry:
  type == "object"
  and (.field | text)
  and (.source_path | text)
  and (.extraction_method | text);
def requirement:
  type == "object"
  and (.id | text)
  and (.text | text)
  and (.status | nullable_text);
def plan:
  type == "object"
  and (.source_path | text)
  and (.title | nullable_text)
  and (.status | nullable_text)
  and (.content | nullable_content)
  and (.summary_present | . == null or type == "boolean")
  and (.depends_on | nullable_array);
def skipped_entry:
  type == "object"
  and (.path | text)
  and (.reason | text);

if type != "object" then error("IR must be an object")
elif .schema_version != 1 then error("IR schema_version must be 1")
elif (.source | type) != "object" then error("IR source is required")
elif ((.source.system | type) != "string" or (.source.system | IN("gsd", "markdown") | not)) then error("IR source system is invalid")
elif ((.source.trust_tier | type) != "string" or (.source.trust_tier | IN("verified-adapter", "unverified-markdown") | not)) then error("IR trust tier is invalid")
elif (.source.root | text | not) then error("IR source root is invalid")
elif (.source.digest | test("^sha256:[0-9a-f]{64}$") | not) then error("IR source digest is invalid")
elif (.project | type) != "object" then error("IR project is required")
elif ((.requirements | type) != "array") or (all(.requirements[]; requirement) | not) then error("IR requirements are invalid")
elif ((.milestones | type) != "array") or (all(.milestones[]; type == "object" and (.name | text)) | not) then error("IR milestones are invalid")
elif ((.phases | type) != "array") or (all(.phases[]; type == "object" and (.slug | text)) | not) then error("IR phases are invalid")
elif ((.plans | type) != "array") or (all(.plans[]; plan) | not) then error("IR plans are invalid")
elif ((.source.skipped_files != null) and (((.source.skipped_files | type) != "array") or (all(.source.skipped_files[]; skipped_entry) | not))) then error("IR skipped files are invalid")
elif ((.decisions | type) != "array") or (all(.decisions[]; type == "object" and (.text | text)) | not) then error("IR decisions are invalid")
elif ((.warnings | type) != "array") or (all(.warnings[]; text) | not) then error("IR warnings are invalid")
elif ((.conflicts | type) != "array") or (all(.conflicts[]; type == "object") | not) then error("IR conflicts are invalid")
elif ((.provenance | type) != "array") or (all(.provenance[]; provenance_entry) | not) then error("IR provenance is invalid")
else .
end
