# test for vector2tile for use in jedi-fv3
add_test(NAME test_vector2tile
         COMMAND ${PROJECT_SOURCE_DIR}/test/test_vector2tile.sh ${PROJECT_BINARY_DIR} ${PROJECT_SOURCE_DIR} vector2tile bkg
         WORKING_DIRECTORY ${PROJECT_BINARY_DIR}/test)
set_tests_properties(test_vector2tile
    PROPERTIES
    ENVIRONMENT "LANDDA_TESTDATA=$ENV{LANDDA_TESTDATA}")

# test for creating IMS ioda ibs file for use in letkfoi
add_test(NAME test_ims2ioda
         COMMAND ${PROJECT_SOURCE_DIR}/test/test_imsproc.sh ${PROJECT_BINARY_DIR} ${PROJECT_SOURCE_DIR}
         WORKING_DIRECTORY ${PROJECT_BINARY_DIR}/test)
set_tests_properties(test_ims2ioda
    PROPERTIES
    DEPENDS     "test_vector2tile"
    ENVIRONMENT "LANDDA_TESTDATA=$ENV{LANDDA_TESTDATA}")

# test for creating pseudo ensemble for use in letkfoi
add_test(NAME test_create_ens
         COMMAND ${PROJECT_SOURCE_DIR}/test/create_bkg_ens.sh ${PROJECT_BINARY_DIR} ${PROJECT_SOURCE_DIR}
         WORKING_DIRECTORY ${PROJECT_BINARY_DIR}/test)
set_tests_properties(test_create_ens
    PROPERTIES
    DEPENDS     "test_vector2title"
    ENVIRONMENT "LANDDA_TESTDATA=$ENV{LANDDA_TESTDATA}") 

# test for running letkfoi to assimilate snow DA
add_test(NAME test_letkfoi_snowda
         COMMAND ${PROJECT_SOURCE_DIR}/test/test_letkfoi_snowda.sh ${PROJECT_BINARY_DIR} ${PROJECT_SOURCE_DIR}
         WORKING_DIRECTORY ${PROJECT_BINARY_DIR}/test)
set_tests_properties(test_letkfoi_snowda
    PROPERTIES
    DEPENDS "test_ims2ioda;test_create_ens"
    ENVIRONMENT "LANDDA_TESTDATA=$ENV{LANDDA_TESTDATA}")

# test for adding jedi increment
add_test(NAME test_apply_jediincr
         COMMAND ${PROJECT_SOURCE_DIR}/test/apply_jedi_incr.sh ${PROJECT_BINARY_DIR} ${PROJECT_SOURCE_DIR}
         WORKING_DIRECTORY ${PROJECT_BINARY_DIR}/test)
set_tests_properties(test_apply_jediincr
    PROPERTIES
    DEPENDS "test_letkfoi_snowda"
    ENVIRONMENT "LANDDA_TESTDATA=$ENV{LANDDA_TESTDATA}")

# test for tile2vector for use in ufs-land-driver
add_test(NAME test_tile2vector
         COMMAND ${PROJECT_SOURCE_DIR}/test/test_vector2tile.sh ${PROJECT_BINARY_DIR} ${PROJECT_SOURCE_DIR} tile2vector ana
         WORKING_DIRECTORY ${PROJECT_BINARY_DIR}/test)
set_tests_properties(test_tile2vector
    PROPERTIES
    DEPENDS "test_apply_jediincr" 
    ENVIRONMENT "LANDDA_TESTDATA=$ENV{LANDDA_TESTDATA}")

# test for ufs-land-driver
add_test(NAME test_land_driver
         COMMAND ${PROJECT_SOURCE_DIR}/test/test_ufs_land_driver.sh ${PROJECT_BINARY_DIR} ${PROJECT_SOURCE_DIR}
         WORKING_DIRECTORY ${PROJECT_BINARY_DIR}/test)
set_tests_properties(test_land_driver
    PROPERTIES
    DEPENDS "test_tile2vector"
    ENVIRONMENT "LANDDA_TESTDATA=$ENV{LANDDA_TESTDATA}")
