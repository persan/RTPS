------------------------------------------------------------------------------
--  RTPS.Entities -- body: GUID ordering relations
--
--  Ordering is lexicographic over the raw octets, so GUIDs can be used
--  directly as keys in ordered containers.
------------------------------------------------------------------------------

package body RTPS.Entities is

   function "=" (L, R : RTPS.Types.EntityId_T) return Boolean is
   begin
      for K in L'Range loop
         if L (K) /= R (K) then
            return False;
         end if;
      end loop;
      return True;
   end "=";

   function "<" (L, R : RTPS.Types.EntityId_T) return Boolean is
   begin
      for K in L'Range loop
         if L (K) < R (K) then
            return True;
         elsif L (K) > R (K) then
            return False;
         end if;
      end loop;
      return False;
   end "<";

   function "=" (L, R : RTPS.Types.GuidPrefix_T) return Boolean is
   begin
      for K in L'Range loop
         if L (K) /= R (K) then
            return False;
         end if;
      end loop;
      return True;
   end "=";

   function "<" (L, R : RTPS.Types.GuidPrefix_T) return Boolean is
   begin
      for K in L'Range loop
         if L (K) < R (K) then
            return True;
         elsif L (K) > R (K) then
            return False;
         end if;
      end loop;
      return False;
   end "<";

   function "=" (L, R : RTPS.Types.GUID_T) return Boolean is
   begin
      return L.Guid_Prefix = R.Guid_Prefix and then L.Entity_Id = R.Entity_Id;
   end "=";

   function "<" (L, R : RTPS.Types.GUID_T) return Boolean is
   begin
      if L.Guid_Prefix < R.Guid_Prefix then
         return True;
      elsif R.Guid_Prefix < L.Guid_Prefix then
         return False;
      else
         return L.Entity_Id < R.Entity_Id;
      end if;
   end "<";

end RTPS.Entities;