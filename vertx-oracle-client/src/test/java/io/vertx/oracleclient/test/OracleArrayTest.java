package io.vertx.oracleclient.test;

import io.vertx.ext.unit.TestContext;
import io.vertx.ext.unit.junit.VertxUnitRunner;
import io.vertx.oracleclient.OracleBuilder;
import io.vertx.oracleclient.OracleConnection;
import io.vertx.oracleclient.test.junit.OracleRule;
import io.vertx.sqlclient.Pool;
import io.vertx.sqlclient.Tuple;
import org.junit.After;
import org.junit.Before;
import org.junit.ClassRule;
import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(VertxUnitRunner.class)
public class OracleArrayTest extends OracleTestBase {

  @ClassRule
  public static OracleRule oracle = OracleRule.SHARED_INSTANCE;

  Pool pool;

  @Before
  public void setUp(TestContext ctx) throws Exception {
    pool = OracleBuilder.pool( builder -> builder
      .connectingTo(oracle.options())
      .using(vertx));
    pool.query("TRUNCATE TABLE StringsArrayTable").execute().onComplete(ctx.asyncAssertSuccess());
  }

  @Test
  public void testStringArray(TestContext ctx) {
    String[] elements = {"str1", "str2", "str3"};
    pool.withConnection(conn -> {
      Object stringsArray = ((OracleConnection)conn).createArray( "STRINGARRAYTYPE", elements );
      String insertSql = "INSERT INTO StringsArrayTable( id, string_array_element) VALUES (?, ?)";
      return conn.preparedQuery( insertSql ).execute( Tuple.of(1, stringsArray) );
    }).onComplete( ctx.asyncAssertSuccess() );
  }

  @After
  public void tearDown(TestContext ctx) throws Exception {
    pool.close().onComplete(ctx.asyncAssertSuccess());
  }
}
